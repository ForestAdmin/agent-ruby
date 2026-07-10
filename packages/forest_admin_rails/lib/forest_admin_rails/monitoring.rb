require 'json'
require 'logger'
require 'active_support/notifications'
require 'active_support/isolated_execution_state'
require 'active_support/core_ext/string/filters'

module ForestAdminRails
  # Opt-in log subscriber for Forest agent monitoring events.
  #
  # The agent only *emits* ActiveSupport::Notifications (`*.forest_admin`); this
  # is a convenience sink that turns them into structured log lines, so most
  # clients get monitoring by flipping one config flag instead of writing a
  # subscriber. Ships disabled. Enable via:
  #
  #   ForestAdminRails.configure do |config|
  #     config.monitoring = { enabled: true }   # see DEFAULTS for all options
  #   end
  #
  # Output defaults to STDOUT + JSON tagged with "source":"forest_admin", so it
  # is auto-collected by Datadog/CloudWatch/k8s and filterable even when mixed
  # with the Rails log. Point `output` at a file path or your own Logger to keep
  # it separate. Advanced backends (StatsD, Sentry, OTel) subscribe in code.
  module Monitoring
    DEFAULTS = {
      enabled: false,
      output: :stdout,        # :stdout | "path/to.log" (rotated) | a Logger instance
      format: :json,          # :json | :text
      ignore: %w[hook],       # event short-names to drop (name without ".forest_admin")
      sql_level: 'off',       # off (group by query name) | medium (by SQL shape) | full (per query)
      sql_truncate: 200,      # max SQL length shown at the :medium level
      sql_summary_top: 15,    # distinct queries listed per request summary
      slow_threshold_ms: 0,   # only log forest events at least this slow
      source: 'forest_admin'  # discriminator field, so mixed streams stay filterable
    }.freeze

    # Carries Rails' X-Request-Id onto a thread-local so every event of a request
    # shares one correlation id (also matching Rails / load-balancer logs).
    class RequestTagger
      def initialize(app)
        @app = app
      end

      def call(env)
        Thread.current[:forest_request_id] = env['action_dispatch.request_id']
        @app.call(env)
      ensure
        Thread.current[:forest_request_id] = nil
      end
    end

    class << self
      # Called from the engine at boot. Reads config, and if enabled wires the
      # correlation middleware, a logger, and the notification subscribers.
      def install!(app)
        config = DEFAULTS.merge((ForestAdminRails.config[:monitoring] || {}).transform_keys(&:to_sym))
        return unless config[:enabled]
        return if @installed

        @installed = true
        insert_middleware(app)
        subscribe!(build_logger(config[:output]), config)
      end

      # Registers the subscribers against a given logger. Returns the subscriber
      # handles so callers (and tests) can tear them down. Kept app-free so it is
      # unit-testable without booting Rails.
      def subscribe!(logger, options = {})
        config = DEFAULTS.merge(options.transform_keys(&:to_sym))
        ignore = config[:ignore].map(&:to_s)

        handles = []
        handles << subscribe_events(logger, config, ignore)
        handles << subscribe_request_scope(logger, config)
        handles << subscribe_sql(logger, config)
        handles
      end

      private

      def subscribe_events(logger, config, ignore)
        ActiveSupport::Notifications.subscribe(/\.forest_admin$/) do |*args|
          event = ActiveSupport::Notifications::Event.new(*args)
          short = event.name.delete_suffix('.forest_admin')
          next if ignore.include?(short)
          next if event.duration < config[:slow_threshold_ms]

          write(logger, config, name: event.name, duration_ms: event.duration,
                                payload: event.payload.except(:exception, :exception_object),
                                error: event.payload[:exception_object])
        end
      end

      # Scopes SQL logging to Forest requests (start fires before any nested SQL)
      # and flushes the per-request SQL summary on finish for the off/medium tiers.
      def subscribe_request_scope(logger, config)
        ActiveSupport::Notifications.subscribe('request.forest_admin', RequestScope.new(logger, config))
      end

      def subscribe_sql(logger, config)
        full = config[:sql_level].to_s == 'full'

        ActiveSupport::Notifications.subscribe('sql.active_record') do |*args|
          event = ActiveSupport::Notifications::Event.new(*args)
          next unless Thread.current[:forest_in_request]
          next if event.payload[:name] == 'SCHEMA' || event.payload[:cached]

          if full
            write(logger, config, name: 'sql.active_record', duration_ms: event.duration,
                                  payload: { name: event.payload[:name], sql: event.payload[:sql].to_s.squish })
          else
            acc = (Thread.current[:forest_sql_acc] ||= {})
            key = if config[:sql_level].to_s == 'medium'
                    event.payload[:sql].to_s.squish[0, config[:sql_truncate]]
                  else
                    event.payload[:name] || 'SQL'
                  end
            entry = (acc[key] ||= { count: 0, ms: 0.0 })
            entry[:count] += 1
            entry[:ms] += event.duration
          end
        end
      end

      # Emits one line in the configured format, tagged with the source so a mixed
      # stream stays filterable.
      def write(logger, config, event)
        request_id = Thread.current[:forest_request_id]
        name = event[:name]
        duration_ms = event[:duration_ms]
        payload = event[:payload] || {}
        error = event[:error]

        if config[:format].to_s == 'text'
          line = "#{name.to_s.ljust(28)} #{duration_ms.round(2)}ms [#{request_id || "-"}] #{payload.inspect}"
          line += " ERROR=#{error.class}: #{error.message}" if error
          logger.info(line)
        else
          data = { source: config[:source], event: name, duration_ms: duration_ms.round(2),
                   request_id: request_id }.merge(payload)
          data[:error] = "#{error.class}: #{error.message}" if error
          logger.info(JSON.generate(data.compact))
        end
      end

      def build_logger(output)
        case output
        when Logger then output
        when String then formatted(Logger.new(log_path(output), 5, 100 * 1024 * 1024))
        else formatted(Logger.new($stdout))
        end
      end

      # We pass fully-formatted messages (a JSON string or a text line), so strip
      # Logger's default severity/timestamp prefix.
      def formatted(logger)
        logger.formatter = proc { |_severity, _time, _progname, msg| "#{msg}\n" }
        logger
      end

      def log_path(path)
        defined?(Rails) && Rails.respond_to?(:root) && Rails.root ? Rails.root.join(path) : path
      end

      def insert_middleware(app)
        return unless app&.config&.middleware

        app.config.middleware.insert_after(ActionDispatch::RequestId, RequestTagger)
      rescue StandardError
        app.config.middleware.use(RequestTagger)
      end
    end

    # Object subscriber: needs start/finish (not just finish), to bracket the
    # request's SQL and flush its summary.
    class RequestScope
      def initialize(logger, config)
        @logger = logger
        @config = config
        @summarise = config[:sql_level].to_s != 'full'
      end

      def start(_name, _id, _payload)
        Thread.current[:forest_in_request] = true
        Thread.current[:forest_sql_acc] = {} if @summarise
      end

      def finish(_name, _id, _payload)
        Thread.current[:forest_in_request] = false
        acc = Thread.current[:forest_sql_acc]
        Thread.current[:forest_sql_acc] = nil
        flush(acc) if @summarise && acc && !acc.empty?
      end

      private

      def flush(acc)
        ranked = acc.sort_by { |_key, v| -v[:count] }
        top = ranked.first(@config[:sql_summary_top])
        payload = {
          queries: acc.values.sum { |v| v[:count] },
          dropped: [ranked.size - top.size, 0].max,
          breakdown: top.map { |key, v| { query: key, count: v[:count], ms: v[:ms].round(2) } }
        }
        total_ms = acc.values.sum { |v| v[:ms] }
        Monitoring.send(:write, @logger, @config, name: 'sql.summary', duration_ms: total_ms, payload: payload)
      end
    end
  end
end
