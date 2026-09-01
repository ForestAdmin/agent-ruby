module ForestAdminDatasourcePylon
  # Long by line count only: the public surface is one explicit method per Pylon
  # endpoint, each delegating to the shared helpers below.
  class Client # rubocop:disable Metrics/ClassLength
    include Writes

    MAX_SEARCH_LIMIT = 1000

    # Bounds `collect_pages`, which asks for a whole dataset rather than a
    # window: the endpoints it reads answer in one response, so reaching this
    # many pages means the API started paginating on its own and the walk is
    # spending more of the per-minute budget than the answer is worth.
    #
    # What reaching it costs is the caller's to say: a conversation thread and a
    # custom-field list are truncated with a warning, where a collection whose
    # answer is only correct whole is refused. See `refuse_past_cap`.
    MAX_COLLECTED_PAGES = 10

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

    # The whole conversation of an issue, oldest message first, or nil when the
    # thread could not be read.
    #
    # `limit` is left out on purpose: Pylon then answers with every message in a
    # single response. Asking for a page would hand back the OLDEST messages and
    # cut the most recent ones off, which is the half of a conversation nobody
    # opens a ticket to read.
    #
    # The cursor is still followed, defensively: Pylon paginates this endpoint
    # when asked to, so a future default page size stays handled rather than
    # silently truncating the thread.
    def fetch_issue_messages(issue_id)
      path = "issues/#{Faraday::Utils.escape(issue_id)}/messages"

      best_effort("fetch_issue_messages(#{issue_id})", default: nil) { must_succeed(path) { collect_pages(path) } }
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

    # The custom-field definitions of one object type. `object_type` is
    # mandatory on this endpoint, so a schema spanning several collections costs
    # one call per collection rather than one call in total.
    #
    # Degrades to nil: this is read while the agent boots, and a token missing
    # the permission — or a Pylon that happens to be down right then — has to
    # cost the operator the custom columns, not the whole datasource.
    #
    # nil rather than an empty list so the caller can tell a failure from an
    # organization that defined no custom field, the two costing very different
    # things: the second says nothing about the next object type, the first says
    # it will almost certainly fail the same way.
    #
    # Which is why it goes through `boot_connection`: a call declared best-effort
    # has no business holding the boot for the minutes the resilient policy is
    # willing to spend waiting a 429 out. The bound is per request, and the walk
    # is allowed the same pages as any other — one is what this endpoint answers
    # with, having a handful of definitions to return per object type.
    def fetch_custom_fields(object_type)
      params = { 'object_type' => object_type }

      best_effort("fetch_custom_fields(#{object_type})", default: nil) do
        must_succeed('custom-fields') { collect_pages('custom-fields', params, conn: boot_connection) }
      end
    end

    # The two memoized connections carry the bearer token in their headers, and
    # `Faraday::Connection#inspect` prints those in clear: a Client reaching an
    # `inspect` by accident leaks the credential whatever `Configuration` does
    # about its own. Masked here for that reason, and not only for symmetry.
    #
    # The url goes through `redacted_url`, not `url`: a base url fronted by an
    # egress proxy carries that proxy's credentials in its user-info, and this
    # is one of the two places that print it.
    def inspect
      "#<#{self.class.name} base_url=#{@configuration.redacted_url.inspect}>"
    end

    private

    def search_resource(path, limit:, cursor: nil, filter: nil, search_text: nil)
      body = { 'limit' => clamp_limit(limit) }
      body['cursor']      = cursor unless blank?(cursor)
      body['filter']      = filter unless filter.nil?
      body['search_text'] = search_text unless blank?(search_text)

      must_succeed(path) { to_search_page(connection.post(path, body).body, path) }
    end

    # `limit` is mandatory on the paginated GET endpoints, unlike their POST
    # /search counterparts which default it server-side.
    def list_resource(path, limit:, cursor: nil)
      params = { 'limit' => clamp_limit(limit) }
      params['cursor'] = cursor unless blank?(cursor)

      must_succeed(path) { to_search_page(connection.get(path, params).body, path) }
    end

    # The endpoints documented as answering with the whole collection in one
    # response, `GET /users` and `GET /teams`. The cursor is still followed, the
    # way `fetch_issue_messages` follows it: Pylon advertises no next page here,
    # so the walk costs the single request it always did and only does something
    # the day that changes.
    #
    # Past the cap the walk is refused rather than truncated, unlike the thread
    # and the custom fields: `FetchAllCollection` filters, sorts, counts and
    # groups in memory over what this returns, and calls the result exact
    # BECAUSE it is every record Pylon holds. Truncated, that claim would stand
    # over a fraction of the collection -- a count answered short and presented
    # as exact, which is the one answer this datasource refuses everywhere else.
    def fetch_all(path, params = {})
      must_succeed(path) { collect_pages(path, params, refuse_past_cap: true) }
    end

    # Every record of a cursor-paginated GET, no window asked for and no limit
    # sent. `CursorWalker` answers the other question — the offset/limit window a
    # list view asks for — and is not what this needs.
    #
    # `params` ride along on every page, cursor included: a mandatory parameter
    # dropped on the second request answers a different question than the first.
    #
    # An empty page, a cursor that does not move and a cursor already followed
    # all stop the loop: none happens today, but a walk driven by a remote value
    # stops on its own terms rather than collecting the same page twice over.
    #
    # `conn` is what a caller reading on the boot path hands its own connection
    # through: every page of the walk is then bounded like the first.
    #
    # `refuse_past_cap` is for the caller whose answer is only correct whole: the
    # cap then raises instead of logging what it left out. See `fetch_all`.
    def collect_pages(path, params = {}, conn: connection, refuse_past_cap: false)
      records = []
      cursor = nil
      seen = Set.new
      pages = 0

      loop do
        query = cursor.nil? ? params : params.merge('cursor' => cursor)
        page = to_search_page(conn.get(path, query).body, path)
        records.concat(page.records)
        pages += 1
        break if page.next_cursor.nil? || page.records.empty? || !seen.add?(page.next_cursor)

        if pages >= MAX_COLLECTED_PAGES
          refuse_pagination_cap(path, pages, records.size) if refuse_past_cap

          log_pagination_cap(path, pages, records.size)
          break
        end

        cursor = page.next_cursor
      end

      records
    end

    # Refused as an APIError, like a body whose shape broke the contract: what
    # happened is that Pylon started answering an endpoint differently, which no
    # filter the operator sets and no page they ask for would work around.
    def refuse_pagination_cap(path, pages, collected)
      raise APIError,
            "Pylon paginated #{path} past the #{pages} pages this walk covers (#{collected} records read). " \
            'That endpoint is documented as answering with the whole collection in one response, which is what ' \
            'PylonUser and PylonTeam filter, sort and count in memory as an exact answer. Refusing rather ' \
            'than answering over a fraction of the collection: reading it needs cursor pagination, the way ' \
            'PylonIssue reads its own.'
    end

    def log_pagination_cap(path, pages, collected)
      ForestAdminDatasourcePylon.logger.warn(
        "[forest_admin_datasource_pylon] Stopped paginating #{path} after #{pages} page(s) / " \
        "#{collected} record(s); the rest is left out."
      )
    end

    # The id comes from operator-supplied filter values, so it is escaped before
    # being joined to the path.
    def fetch_resource(resource, id)
      path = "#{resource}/#{Faraday::Utils.escape(id)}"
      must_succeed(path) { extract_record(connection.get(path).body, path) }
    end

    def clamp_limit(limit)
      value = limit.to_i
      return 1 if value < 1

      [value, MAX_SEARCH_LIMIT].min
    end

    # Pylon only includes the `pagination` block when a next page exists, so an
    # absent block, `has_next_page: false` and an empty cursor all mean "done".
    def to_search_page(body, operation)
      pagination = body.is_a?(Hash) ? body['pagination'] : nil
      cursor = pagination.is_a?(Hash) && pagination['has_next_page'] ? pagination['cursor'] : nil

      SearchPage.new(records: extract_list(body, operation), next_cursor: blank?(cursor) ? nil : cursor)
    end

    # A read expects `data` to hold what it asked for, and anything else broke
    # the contract. `extract_data` hands an envelope carrying no `data` straight
    # back, which `Array()` would then split into `[key, value]` pairs and the
    # collection would serialize into rows holding nothing -- a page that looks
    # answered and is empty. Refused instead, the way the write path already
    # refuses the same shape: see `Client::Writes#extract_written`.
    #
    # An absent or null `data` stays the empty answer it is: Pylon spells "no
    # record" that way, and a search matching nothing is not a broken contract.
    def extract_list(body, operation)
      data = extract_data(body)
      return [] if data.nil?
      return data if data.is_a?(Array)

      refuse_body_shape(body, operation, "'data' is not a list")
    end

    # The single-record half of the same check. nil travels: it is what a
    # caller reads as "no such record".
    def extract_record(body, operation)
      data = extract_data(body)
      return data if data.nil? || data.is_a?(Hash)

      refuse_body_shape(body, operation, "'data' is not a record")
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

    # For the calls whose result enriches a page rather than being the page: the
    # failure is reported and the default returned, so a degraded thread or a
    # missing enrichment costs the operator a column, not the record they opened.
    def best_effort(operation, default:)
      yield
    rescue StandardError => e
      ForestAdminDatasourcePylon.logger.warn(
        "[forest_admin_datasource_pylon] #{operation} failed; degrading: #{e.class}: #{e.message}"
      )
      default
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

    def connection
      @connection ||= build_connection(
        retry_policy: @configuration.retry_policy,
        timeout: @configuration.timeout,
        open_timeout: @configuration.open_timeout
      )
    end

    # For what is read while the datasource is being constructed: short timeouts
    # and one quick retry, so the introspection cannot turn a Pylon that is down
    # into minutes of Rails boot. Memoized separately from `connection`, which
    # keeps the patience every later request is entitled to.
    def boot_connection
      @boot_connection ||= build_connection(
        retry_policy: @configuration.boot_retry_policy,
        timeout: @configuration.boot_timeout,
        open_timeout: @configuration.boot_open_timeout
      )
    end

    # Middleware order is deliberate: `raise_error` sits outside the JSON parser
    # so it raises with an already-parsed body, and `retry` sits innermost so it
    # inspects raw statuses — behind `raise_error` it would never see a 429.
    #
    # The throttle goes inside `retry`, which is what makes a replay wait for a
    # slot like a first attempt: outside it, the middleware would run once for a
    # request that reached Pylon three times.
    #
    # How long a request is allowed to take is the caller's to state, everything
    # else being the same on every connection this builds: the limiter included,
    # a second connection metering in a window of its own spending the budget of
    # the endpoint twice over.
    def build_connection(retry_policy:, timeout:, open_timeout:)
      Faraday.new(url: @configuration.url) do |f|
        f.request :json
        f.response :raise_error
        f.response :json
        f.request :retry, **retry_policy.to_faraday_options
        if @configuration.rate_limiter
          f.use Throttle, limiter: @configuration.rate_limiter, base_path: @configuration.base_path
        end
        f.headers['Authorization'] = "Bearer #{@configuration.api_key}"
        f.headers['Accept']        = 'application/json'
        f.headers['User-Agent']    = "forest_admin_datasource_pylon/#{VERSION}"
        f.options.open_timeout = open_timeout
        f.options.timeout      = timeout
      end
    end
  end
end
