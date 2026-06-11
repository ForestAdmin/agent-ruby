module ForestAdminDatasourceMambuPayments
  # rubocop:disable Metrics/ClassLength
  class Client
    include Reads
    include Writes

    MAX_PER_PAGE = 100

    def initialize(configuration)
      @configuration = configuration
    end

    private

    def list_resource(path, params = {})
      must_succeed("list(#{path})") do
        body = connection.get(path, normalize_params(params)).body
        extract_records(body, path)
      end
    end

    # Server-side count. Numeral list responses carry a `total` field, so we
    # ask for a single record and read the total off the envelope rather than
    # materializing (and capping at one page of) the whole collection.
    def count_resource(path, params = {})
      must_succeed("count(#{path})") do
        body = connection.get(path, normalize_params(params.merge(limit: 1))).body
        extract_total(body, path)
      end
    end

    def get_resource(path, id)
      extract_record(connection.get("#{path}/#{id}").body)
    rescue Faraday::ResourceNotFound
      nil
    rescue Faraday::Error => e
      raise api_error("get(#{path}/#{id})", e)
    rescue StandardError => e
      raise APIError, "Mambu Payments API call failed: get(#{path}/#{id}): #{e.class}: #{e.message}"
    end

    def post_resource(path, attributes)
      must_succeed("create(#{path})") do
        extract_record(connection.post(path, attributes).body)
      end
    end

    def patch_resource(path, id, attributes)
      must_succeed("update(#{path}/#{id})") do
        extract_record(connection.patch("#{path}/#{id}", attributes).body)
      end
    end

    # POST .../:id/:action — Numeral exposes side-effect endpoints (approve,
    # cancel, verify) as sub-paths returning the updated resource.
    def post_action_resource(path, id, action, attributes = {})
      must_succeed("#{action}(#{path}/#{id})") do
        extract_record(connection.post("#{path}/#{id}/#{action}", attributes).body)
      end
    end

    # Numeral list responses are typically wrapped (e.g. { "data": [...] } or
    # { "connected_accounts": [...] }) but we accept a raw array too. Falls back
    # to the first array-valued field so we don't silently coerce a wrapper hash
    # into an array of [key, value] pairs.
    def extract_records(body, path)
      return body if body.is_a?(Array)
      return [] unless body.is_a?(Hash)

      wrapped = body['data'] || body[path] || body['records'] || body['items']
      return wrapped if wrapped.is_a?(Array)

      fallback = body.values.find { |v| v.is_a?(Array) }
      if fallback
        ForestAdminDatasourceMambuPayments.logger.warn(
          "[forest_admin_datasource_mambu_payments] list(#{path}) used wrapper-key fallback; " \
          "body keys=#{body.keys.inspect}"
        )
        return fallback
      end

      []
    end

    def extract_record(body)
      return nil if body.nil?
      return body['data'] if body.is_a?(Hash) && body['data'].is_a?(Hash)

      body
    end

    # Reads the `total` count off a list envelope, falling back to the size of
    # the returned records when the API omits it (e.g. an array body).
    def extract_total(body, path)
      return body['total'].to_i if body.is_a?(Hash) && body.key?('total')

      extract_records(body, path).size
    end

    def delete_resource(path, id)
      must_succeed("delete(#{path}/#{id})") do
        connection.delete("#{path}/#{id}")
        true
      end
    end

    def normalize_params(params)
      params.compact.transform_values { |v| v.is_a?(Array) ? v.join(',') : v }
    end

    def must_succeed(operation)
      yield
    rescue Faraday::Error => e
      raise api_error(operation, e)
    rescue StandardError => e
      raise APIError, "Mambu Payments API call failed: #{operation}: #{e.class}: #{e.message}"
    end

    # Builds an APIError that preserves the HTTP status and the API's own error
    # body. Numeral returns structured validation errors (e.g. on a 422), which
    # smart actions surface to the operator instead of a generic failure string.
    def api_error(operation, error)
      response = error.respond_to?(:response) ? error.response : nil
      status = response.is_a?(Hash) ? response[:status] : nil
      body   = response.is_a?(Hash) ? response[:body] : nil
      detail = error_detail(status, body) || "#{error.class}: #{error.message}"
      APIError.new("Mambu Payments API call failed: #{operation}: #{detail}", status: status, body: parse_body(body))
    end

    def error_detail(status, body)
      return nil unless status

      ["HTTP #{status}", error_message(parse_body(body))].compact.join(' ').strip
    end

    # Pulls the human-readable message out of the common Numeral error shapes
    # ({ "error": { "message": ... } }, { "errors": [...] }, { "message": ... }).
    def error_message(parsed)
      return parsed.to_s[0, 500] unless parsed.is_a?(Hash)

      message = parsed.dig('error', 'message') || parsed['message'] || parsed['detail']
      message ||= Array(parsed['errors']).filter_map do |e|
        e.is_a?(Hash) ? (e['message'] || e['detail']) : e
      end.join('; ')
      (message.to_s.empty? ? parsed.to_json : message)[0, 500]
    end

    def parse_body(body)
      return body unless body.is_a?(String) && !body.empty?

      JSON.parse(body)
    rescue JSON::ParserError
      body
    end

    def best_effort(operation, default:)
      yield
    rescue StandardError => e
      ForestAdminDatasourceMambuPayments.logger.warn(
        "[forest_admin_datasource_mambu_payments] #{operation} failed; degrading: #{e.class}: #{e.message}"
      )
      default
    end

    def connection
      @connection ||= Faraday.new(url: @configuration.url) do |f|
        f.request :json
        f.request :retry, max: 3, interval: 0.2, backoff_factor: 2,
                          retry_statuses: [429, 502, 503, 504]
        f.response :json
        f.response :raise_error
        f.headers['x-api-key']  = @configuration.api_key
        f.headers['Accept']     = 'application/json'
        f.headers['User-Agent'] = "forest_admin_datasource_mambu_payments/#{VERSION}"
        f.options.open_timeout = @configuration.open_timeout
        f.options.timeout      = @configuration.timeout
      end
    end
  end
  # rubocop:enable Metrics/ClassLength
end
