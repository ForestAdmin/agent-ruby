module ForestAdminDatasourcePylon
  # Long by line count only: the public surface is one explicit method per Pylon
  # endpoint, each delegating to the shared helpers below.
  class Client # rubocop:disable Metrics/ClassLength
    MAX_SEARCH_LIMIT = 1000

    # `next_cursor` is nil as soon as Pylon stops advertising a next page, so
    # callers never have to know how the absence is spelled on the wire.
    SearchPage = Struct.new(:records, :next_cursor, keyword_init: true)

    def initialize(configuration)
      @configuration = configuration
    end

    # Health check: Pylon returns the details of the organization owning the
    # token, which is enough to prove the credentials are usable.
    def me
      must_succeed('me') { extract_data(connection.get('me').body) }
    end

    # POST /issues/search accepts an empty body and then returns the most recent
    # issues, ordered by `created_at` descending.
    def search_issues(limit:, cursor: nil, filter: nil, search_text: nil)
      search_resource('issues/search', limit: limit, cursor: cursor, filter: filter, search_text: search_text)
    end

    # Accepts either the UUID or the issue number.
    def fetch_issue(id)
      fetch_resource('issues', id)
    end

    def search_accounts(limit:, cursor: nil, filter: nil, search_text: nil)
      search_resource('accounts/search', limit: limit, cursor: cursor, filter: filter, search_text: search_text)
    end

    def list_accounts(limit:, cursor: nil)
      list_resource('accounts', limit: limit, cursor: cursor)
    end

    # Accepts either the Pylon UUID or the account's external id.
    def fetch_account(id)
      fetch_resource('accounts', id)
    end

    def search_contacts(limit:, cursor: nil, filter: nil, search_text: nil)
      search_resource('contacts/search', limit: limit, cursor: cursor, filter: filter, search_text: search_text)
    end

    # GET /contacts is paginated exactly like GET /accounts even though the
    # OpenAPI spec forgets to document its query parameters.
    def list_contacts(limit:, cursor: nil)
      list_resource('contacts', limit: limit, cursor: cursor)
    end

    def fetch_contact(id)
      fetch_resource('contacts', id)
    end

    # GET /users is unpaginated. Deactivated agents are included by default so
    # that assignees of older issues stay resolvable.
    def fetch_users(include_deactivated: true)
      fetch_all('users', 'include_deactivated' => include_deactivated)
    end

    def fetch_user(id)
      fetch_resource('users', id)
    end

    # GET /teams is unpaginated and takes no parameter.
    def fetch_teams
      fetch_all('teams')
    end

    def fetch_team(id)
      fetch_resource('teams', id)
    end

    private

    def search_resource(path, limit:, cursor: nil, filter: nil, search_text: nil)
      body = { 'limit' => clamp_limit(limit) }
      body['cursor']      = cursor unless blank?(cursor)
      body['filter']      = filter unless filter.nil?
      body['search_text'] = search_text unless blank?(search_text)

      must_succeed(path) { to_search_page(connection.post(path, body).body) }
    end

    # `limit` is mandatory on the paginated GET endpoints, unlike their POST
    # /search counterparts which default it server-side.
    def list_resource(path, limit:, cursor: nil)
      params = { 'limit' => clamp_limit(limit) }
      params['cursor'] = cursor unless blank?(cursor)

      must_succeed(path) { to_search_page(connection.get(path, params).body) }
    end

    def fetch_all(path, params = {})
      must_succeed(path) { Array(extract_data(connection.get(path, params).body)) }
    end

    # The id comes from operator-supplied filter values, so it is escaped before
    # being joined to the path.
    def fetch_resource(resource, id)
      path = "#{resource}/#{Faraday::Utils.escape(id)}"
      must_succeed(path) { extract_data(connection.get(path).body) }
    end

    def clamp_limit(limit)
      value = limit.to_i
      return 1 if value < 1

      [value, MAX_SEARCH_LIMIT].min
    end

    # Pylon only includes the `pagination` block when a next page exists, so an
    # absent block, `has_next_page: false` and an empty cursor all mean "done".
    def to_search_page(body)
      pagination = body.is_a?(Hash) ? body['pagination'] : nil
      cursor = pagination.is_a?(Hash) && pagination['has_next_page'] ? pagination['cursor'] : nil

      SearchPage.new(records: Array(extract_data(body)), next_cursor: blank?(cursor) ? nil : cursor)
    end

    def blank?(value)
      value.nil? || value.to_s.empty?
    end

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
    rescue APIError
      # Already mapped, with its status intact; re-wrapping would erase it.
      raise
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

      "HTTP #{status} #{error_message(body)}".strip
    end

    def error_message(parsed)
      return parsed.to_s[0, 500] unless parsed.is_a?(Hash)

      nested = parsed['error']
      message = parsed['message'] || (nested.is_a?(Hash) ? nested['message'] : nested) ||
                join_errors(parsed['errors'])
      message = parsed.to_json if message.to_s.empty?
      # Truncate before appending: the request_id is what support needs, so it
      # must not be the first thing a long error body pushes out.
      append_request_id(message.to_s[0, 500], parsed['request_id'])
    end

    def append_request_id(message, request_id)
      return message unless request_id

      "#{message} (request_id: #{request_id})"
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
        f.request :retry, **@configuration.retry_policy.to_faraday_options
        f.headers['Authorization'] = "Bearer #{@configuration.api_key}"
        f.headers['Accept']        = 'application/json'
        f.headers['User-Agent']    = "forest_admin_datasource_pylon/#{VERSION}"
        f.options.open_timeout = @configuration.open_timeout
        f.options.timeout      = @configuration.timeout
      end
    end
  end
end
