require 'faraday'

module ForestAdminAgent
  module Routes
    module Workflow
      # Forwards workflow-execution traffic from the agent to the workflow executor.
      # Mounted only when the integrator sets `workflow_executor_url`
      class WorkflowExecutorProxy < AbstractAuthenticatedRoute
        AGENT_PREFIX = '/_internal/workflow-executions'.freeze
        EXECUTOR_PREFIX = '/runs'.freeze
        FORWARDED_HEADERS = %w[Authorization Cookie].freeze
        ROUTING_KEYS = %w[run_id route_alias controller action format].freeze

        def setup_routes
          return self unless executor_configured?

          add_route(
            'forest_workflow_run_show',
            'get',
            "#{AGENT_PREFIX}/:run_id",
            ->(args) { handle_request(:get, args) }
          )
          add_route(
            'forest_workflow_run_trigger',
            'post',
            "#{AGENT_PREFIX}/:run_id/trigger",
            ->(args) { handle_request(:post, args) }
          )

          self
        end

        def handle_request(method, args = {})
          build(args)

          base_url = configured_executor_url
          run_id = args.dig(:params, 'run_id') || args.dig(:params, :run_id)
          path = build_path(run_id, method)
          response = forward(method, base_url, path, args)

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

        def build_path(run_id, method)
          suffix = method == :post ? '/trigger' : ''
          "#{EXECUTOR_PREFIX}/#{run_id}#{suffix}"
        end

        def forward(method, base_url, path, args)
          query = forwarded_query_params(args[:params])
          headers = forwarded_request_headers(args[:headers])
          body = forwarded_body(method, args[:params])
          target_url = "#{base_url}#{path}"

          client = build_client
          client.run_request(method, target_url, body, headers) do |req|
            req.params.update(query) unless query.empty?
          end
        rescue Faraday::TimeoutError => e
          raise Http::Exceptions::ServiceUnavailableError.new('Workflow executor timed out', cause: e)
        rescue Faraday::ConnectionFailed => e
          raise Http::Exceptions::ServiceUnavailableError.new('Workflow executor unreachable', cause: e)
        end

        def build_client
          Faraday.new do |f|
            f.request :json
            f.response :json, content_type: /\bjson$/
            f.adapter Faraday.default_adapter
          end
        end

        # Strip Rails-injected routing keys; keep only true client query params.
        def forwarded_query_params(params)
          return {} unless params.is_a?(Hash)

          params.each_with_object({}) do |(key, value), acc|
            next if ROUTING_KEYS.include?(key.to_s)
            next if value.is_a?(Hash) || value.is_a?(Array) # 'data' body, etc.

            acc[key.to_s] = value
          end
        end

        def forwarded_request_headers(headers)
          return {} unless headers.is_a?(Hash)

          FORWARDED_HEADERS.each_with_object({}) do |name, acc|
            value = headers[name] || headers[name.downcase] || headers["HTTP_#{name.upcase}"]
            acc[name] = value if value && !value.to_s.empty?
          end
        end

        def forwarded_body(method, params)
          return nil if method == :get
          return nil unless params.is_a?(Hash)

          # JSON request bodies arrive parsed under :data when sent as JSON:API,
          # or as the raw top-level params hash otherwise. Prefer :data when
          # present; fall back to a sanitized copy of params.
          body = params['data'] || params[:data]
          return body if body

          params.reject { |key, _| ROUTING_KEYS.include?(key.to_s) }
        end

        def forwarded_response_headers(response)
          content_type = response.headers['content-type'] || response.headers['Content-Type']
          content_type ? { 'Content-Type' => content_type } : {}
        end
      end
    end
  end
end
