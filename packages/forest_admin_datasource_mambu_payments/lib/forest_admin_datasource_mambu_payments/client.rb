module ForestAdminDatasourceMambuPayments
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

    def get_resource(path, id)
      extract_record(connection.get("#{path}/#{id}").body)
    rescue Faraday::ResourceNotFound
      nil
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
    rescue StandardError => e
      raise APIError, "Mambu Payments API call failed: #{operation}: #{e.class}: #{e.message}"
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
end
