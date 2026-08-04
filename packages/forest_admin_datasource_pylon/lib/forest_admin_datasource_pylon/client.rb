module ForestAdminDatasourcePylon
  class Client
    RETRY_STATUSES = [429, 502, 503, 504].freeze

    # Faraday only retries these by default; a 429 is safe to retry on any verb
    # because Pylon rejected the request before processing it, whereas a 502 on a
    # POST /issues may well have created the issue.
    IDEMPOTENT_METHODS = %i[delete get head options put].freeze
    RETRY_IF = ->(env, _exception) { env[:status] == 429 }

    def initialize(configuration)
      @configuration = configuration
    end

    # Health check: Pylon returns the details of the organization owning the
    # token, which is enough to prove the credentials are usable.
    def me
      must_succeed('me') { extract_data(connection.get('me').body) }
    end

    private

    # Pylon wraps payloads in { "data": ..., "pagination": ..., "request_id": ... }.
    def extract_data(body)
      return nil if body.nil? || body == ''
      return body['data'] if body.is_a?(Hash) && body.key?('data')

      body
    end

    def must_succeed(operation)
      yield
    rescue Faraday::Error => e
      raise api_error(operation, e)
    rescue StandardError => e
      raise APIError, "Pylon API call failed: #{operation}: #{e.class}: #{e.message}"
    end

    # Builds an APIError preserving the HTTP status and Pylon's own error body so
    # smart actions can show the operator the real reason instead of "failed".
    def api_error(operation, error)
      response = error.respond_to?(:response) ? error.response : nil
      status = response.is_a?(Hash) ? response[:status] : nil
      body   = parse_body(response.is_a?(Hash) ? response[:body] : nil)
      detail = error_detail(status, body) || "#{error.class}: #{error.message}"
      APIError.new("Pylon API call failed: #{operation}: #{detail}", status: status, body: body)
    end

    def error_detail(status, body)
      return nil unless status

      ["HTTP #{status}", error_message(body)].compact.join(' ').strip
    end

    def error_message(parsed)
      return parsed.to_s[0, 500] unless parsed.is_a?(Hash)

      nested = parsed['error']
      message = parsed['message'] || (nested.is_a?(Hash) ? nested['message'] : nested) ||
                join_errors(parsed['errors'])
      message = parsed.to_json if message.to_s.empty?
      message = "#{message} (request_id: #{parsed["request_id"]})" if parsed['request_id']
      message.to_s[0, 500]
    end

    def join_errors(errors)
      Array(errors).filter_map { |e| e.is_a?(Hash) ? (e['message'] || e['detail']) : e }.join('; ')
    end

    def parse_body(body)
      return body unless body.is_a?(String) && !body.empty?

      JSON.parse(body)
    rescue JSON::ParserError
      body
    end

    # Middleware order is deliberate: `raise_error` sits outside the JSON parser
    # so it raises with an already-parsed body, and `retry` sits innermost so it
    # inspects raw statuses — behind `raise_error` it would never see a 429.
    def connection
      @connection ||= Faraday.new(url: @configuration.url) do |f|
        f.request :json
        f.response :raise_error
        f.response :json
        f.request :retry, max: @configuration.max_retries, interval: @configuration.retry_interval,
                          backoff_factor: 2, max_interval: 5, retry_statuses: RETRY_STATUSES,
                          methods: IDEMPOTENT_METHODS, retry_if: RETRY_IF
        f.headers['Authorization'] = "Bearer #{@configuration.api_key}"
        f.headers['Accept']        = 'application/json'
        f.headers['User-Agent']    = "forest_admin_datasource_pylon/#{VERSION}"
        f.options.open_timeout = @configuration.open_timeout
        f.options.timeout      = @configuration.timeout
      end
    end
  end
end
