require 'faraday'

module ForestAdminAgent
  module Routes
    module Workflow
      # Generic proxy: forwards any sub-path/verb under AGENT_PREFIX to EXECUTOR_PREFIX, so a
      # new executor route needs no change here (PRD-567). Mounted only when `workflow_executor_url` is set.
      class WorkflowExecutorProxy < AbstractAuthenticatedRoute
        AGENT_PREFIX = '/_internal/workflow-executions'.freeze
        EXECUTOR_PREFIX = '/runs'.freeze
        # Hop-by-hop headers + those the HTTP client must recompute — never forwarded.
        SKIPPED_HEADERS = %w[
          connection keep-alive transfer-encoding upgrade te trailer
          proxy-authenticate proxy-authorization host content-length
        ].freeze
        # Substrings that could let the wildcard escape EXECUTOR_PREFIX (traversal, encoded
        # dots, backslash, null byte).
        UNSAFE_PATH_FRAGMENTS = ['..', '%2e', '%2E', '\\', "\0"].freeze
        OPEN_TIMEOUT = 2
        REQUEST_TIMEOUT = 120

        def setup_routes
          return self unless executor_configured?

          # The glob can only ever map into EXECUTOR_PREFIX (build_executor_path rejects
          # traversal), so executor routes outside it stay unreachable through the proxy.
          add_route(
            'forest_workflow_executor_proxy',
            :all,
            "#{AGENT_PREFIX}/*path",
            ->(args) { handle_request(args) }
          )

          self
        end

        def handle_request(args = {})
          build(args)

          method = (args[:method] || 'get').to_s.downcase.to_sym
          response = forward(method, build_target_url(args), args)

          {
            content: response.body,
            status: response.status,
            headers: forwarded_response_headers(response)
          }
        end

        private

        def executor_configured?
          url = ForestAdminAgent::Facades::Container.config_from_cache[:workflow_executor_url]
          !(url.nil? || url.to_s.strip.empty?)
        rescue StandardError
          # Container not yet populated (e.g. boot-order edge case): treat as disabled.
          false
        end

        def configured_executor_url
          url = ForestAdminAgent::Facades::Container.config_from_cache[:workflow_executor_url]
          if url.nil? || url.to_s.strip.empty?
            raise Http::Exceptions::NotFoundError, 'Workflow executor proxy is not configured'
          end

          url.to_s.sub(%r{/+\z}, '')
        end

        def build_target_url(args)
          path = build_executor_path(args.dig(:params, 'path') || args.dig(:params, :path))
          query = args[:query_string].to_s
          url = "#{configured_executor_url}#{path}"

          query.empty? ? url : "#{url}?#{query}"
        end

        # Security boundary: reject anything that could escape EXECUTOR_PREFIX.
        def build_executor_path(raw_path)
          path = raw_path.to_s
          raise Http::Exceptions::NotFoundError, 'Invalid workflow executor path' if unsafe_path?(path)

          "#{EXECUTOR_PREFIX}/#{path}"
        end

        def unsafe_path?(path)
          return true if path.empty? || path.start_with?('/')

          UNSAFE_PATH_FRAGMENTS.any? { |fragment| path.include?(fragment) }
        end

        def forward(method, target_url, args)
          headers = forwarded_request_headers(args[:headers])
          body = method == :get ? nil : args[:body]

          build_client.run_request(method, target_url, body, headers)
        rescue Faraday::TimeoutError => e
          raise Http::Exceptions::ServiceUnavailableError.new('Workflow executor timed out', cause: e)
        rescue Faraday::ConnectionFailed => e
          raise Http::Exceptions::ServiceUnavailableError.new('Workflow executor unreachable', cause: e)
        end

        def build_client
          Faraday.new(request: { open_timeout: OPEN_TIMEOUT, timeout: REQUEST_TIMEOUT }) do |f|
            # No request :json middleware: body is forwarded raw (not reshaped).
            f.response :json, content_type: /\bjson$/
            f.adapter Faraday.default_adapter
          end
        end

        # `env` is the Rack env: real HTTP headers are the HTTP_* keys (+ CONTENT_TYPE);
        # rack.*/action_dispatch.*/server vars are not headers and are dropped.
        def forwarded_request_headers(env)
          return {} unless env.is_a?(Hash)

          env.each_with_object({}) do |(key, value), acc|
            name = http_header_name(key.to_s)
            next unless name
            next if SKIPPED_HEADERS.include?(name.downcase)
            next if value.nil? || value.to_s.empty?

            acc[name] = value.to_s
          end
        end

        def http_header_name(env_key)
          if env_key.start_with?('HTTP_')
            titleize_header(env_key.delete_prefix('HTTP_'))
          elsif %w[CONTENT_TYPE CONTENT_LENGTH].include?(env_key)
            titleize_header(env_key)
          end
        end

        def titleize_header(rack_name)
          rack_name.split('_').map(&:capitalize).join('-')
        end

        # Forward every executor response header except hop-by-hop ones, so the version gate
        # (X-Forest-Executor-Version) survives the proxy.
        def forwarded_response_headers(response)
          response.headers.each_with_object({}) do |(name, value), acc|
            next if name.nil? || SKIPPED_HEADERS.include?(name.to_s.downcase)
            next if value.nil? || value.to_s.empty?

            acc[name.to_s] = value.to_s
          end
        end
      end
    end
  end
end
