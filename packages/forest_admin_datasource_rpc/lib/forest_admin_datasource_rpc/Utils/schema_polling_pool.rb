require 'singleton'

module ForestAdminDatasourceRpc
  module Utils
    # Thread pool manager for RPC schema polling.
    # Uses a single scheduler thread that dispatches polling tasks to a bounded
    # pool of worker threads, preventing thread exhaustion when many RPC slaves
    # are configured.
    #
    # Design principles:
    # - Minimal mutex hold times to avoid blocking HTTP request threads
    # - Workers yield control frequently to prevent GIL starvation
    # - Non-blocking queue operations where possible
    class SchemaPollingPool
      include Singleton

      DEFAULT_MAX_THREADS = 5
      MIN_THREADS = 1
      MAX_THREADS = 50
      SCHEDULER_INTERVAL = 1
      INITIAL_STAGGER_WINDOW = 30

      attr_reader :max_threads, :configured

      def initialize
        @mutex = Mutex.new
        @clients = {}
        @work_queue = Queue.new
        @workers = []
        @running = false
        @max_threads = DEFAULT_MAX_THREADS
        @shutdown_requested = false
        @configured = false
        @scheduler_thread = nil
      end

      # Configure the pool before starting. Must be called before any clients register.
      # @param max_threads [Integer] Maximum number of worker threads (1-20)
      def configure(max_threads:)
        @mutex.synchronize do
          raise 'Cannot configure pool while running' if @running

          validated_max = max_threads.to_i.clamp(MIN_THREADS, MAX_THREADS)
          @max_threads = validated_max
          @configured = true

          log('Info', "[SchemaPollingPool] Configured with max_threads: #{@max_threads}")
        end
      end

      def register?(client_id, client)
        should_start = false

        @mutex.synchronize do
          if @clients.key?(client_id)
            log('Warn', "[SchemaPollingPool] Client #{client_id} already registered, skipping")
            return false
          end

          @clients[client_id] = {
            client: client,
            last_poll_at: nil,
            next_poll_at: calculate_initial_poll_time
          }

          log('Info', "[SchemaPollingPool] Registered client: #{client_id} (#{@clients.size} total clients)")

          should_start = !@running
        end

        start_pool if should_start

        true
      end

      def unregister?(client_id)
        should_stop = false

        @mutex.synchronize do
          unless @clients.key?(client_id)
            log('Debug', "[SchemaPollingPool] Client #{client_id} not found for unregister")
            return false
          end

          @clients.delete(client_id)
          log('Info', "[SchemaPollingPool] Unregistered client: #{client_id} (#{@clients.size} remaining)")

          should_stop = @clients.empty? && @running
        end

        stop_pool if should_stop

        true
      end

      def client_count
        @mutex.synchronize { @clients.size }
      end

      def running?
        @mutex.synchronize { @running }
      end

      def shutdown!
        @mutex.synchronize do
          return unless @running

          @shutdown_requested = true
        end

        stop_pool

        @mutex.synchronize do
          @clients.clear
          @shutdown_requested = false
        end
      end

      def reset!
        shutdown!
        @mutex.synchronize do
          @max_threads = DEFAULT_MAX_THREADS
          @configured = false
        end
      end

      private

      def start_pool
        @mutex.synchronize do
          return if @running

          @running = true
          @shutdown_requested = false

          thread_count = @clients.size.clamp(MIN_THREADS, @max_threads)

          log('Info',
              "[SchemaPollingPool] Starting pool with #{thread_count} worker threads for #{@clients.size} clients")

          thread_count.times do |i|
            @workers << Thread.new { worker_loop(i) }
          end

          @scheduler_thread = Thread.new { scheduler_loop }
        end
      end

      def stop_pool
        workers_to_join = nil
        scheduler_to_join = nil

        @mutex.synchronize do
          return unless @running

          log('Info', '[SchemaPollingPool] Stopping pool...')

          @running = false

          @workers.size.times { @work_queue << nil }

          workers_to_join = @workers.dup
          scheduler_to_join = @scheduler_thread

          @workers.clear
          @scheduler_thread = nil
        end

        workers_to_join&.each { |w| w.join(2) }
        scheduler_to_join&.join(2)

        @work_queue.clear

        log('Info', '[SchemaPollingPool] Pool stopped')
      end

      def worker_loop(worker_id)
        log('Debug', "[SchemaPollingPool] Worker #{worker_id} started")

        loop do
          task = fetch_next_task
          break if task.nil?

          process_task(task, worker_id)
          Thread.pass
        end

        log('Debug', "[SchemaPollingPool] Worker #{worker_id} stopped")
      end

      def fetch_next_task
        @work_queue.pop(true)
      rescue ThreadError
        Thread.pass
        sleep(0.1)
        retry if @running
        nil
      end

      def process_task(task, worker_id)
        client_id = task[:client_id]
        execute_poll(client_id)
      rescue StandardError => e
        log('Error',
            "[SchemaPollingPool] Worker #{worker_id} error polling #{client_id}: #{e.class} - #{e.message}")
      end

      def scheduler_loop
        log('Debug', '[SchemaPollingPool] Scheduler started')

        while @running
          sleep_with_check(SCHEDULER_INTERVAL)

          next unless @running

          schedule_due_polls
        end

        log('Debug', '[SchemaPollingPool] Scheduler stopped')
      end

      def sleep_with_check(duration)
        remaining = duration
        while remaining.positive? && @running
          sleep_time = [remaining, 1.0].min
          sleep(sleep_time)
          remaining -= sleep_time
          Thread.pass
        end
      end

      def schedule_due_polls
        now = Time.now
        polls_to_schedule = []

        @mutex.synchronize do
          @clients.each do |client_id, state|
            next if state[:next_poll_at].nil?
            next if now < state[:next_poll_at]

            polls_to_schedule << client_id

            interval = state[:client].instance_variable_get(:@polling_interval) || 600
            state[:next_poll_at] = now + interval
          end
        end

        polls_to_schedule.each do |client_id|
          @work_queue << { client_id: client_id, scheduled_at: now }
        end
      end

      def execute_poll(client_id)
        client = nil
        @mutex.synchronize do
          state = @clients[client_id]
          client = state[:client] if state
        end

        return unless client
        return if client.closed

        log('Debug', "[SchemaPollingPool] Polling client: #{client_id}")

        client.check_schema

        @mutex.synchronize do
          @clients[client_id][:last_poll_at] = Time.now if @clients[client_id]
        end
      end

      def calculate_initial_poll_time
        # Stagger initial polls to avoid thundering herd
        Time.now + rand(0.0..INITIAL_STAGGER_WINDOW.to_f)
      end

      def log(level, message)
        return unless defined?(ForestAdminAgent::Facades::Container)

        ForestAdminAgent::Facades::Container.logger&.log(level, message)
      rescue StandardError
        # Ignore logging errors to prevent cascading failures
      end
    end
  end
end
