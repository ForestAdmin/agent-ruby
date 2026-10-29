module ForestAdminDatasourceIntercom
  # Hand-written on Faraday rather than the `intercom` gem, to keep raw payloads, quota headers and error bodies.
  # Long by line count only: one method per endpoint plus shared envelope and error handling.
  class Client # rubocop:disable Metrics/ClassLength
    # `per_page=200` is refused with `invalid_per_page` -- "must be an integer
    # between 0 and 150". There is no silent downgrade, so a page size is bounded
    # before it is sent or the list view breaks rather than shrinks.
    MAX_PER_PAGE = 150

    # Bounds `fetch_all`, which asks for a whole reference collection rather than
    # a window: those endpoints answer in one response, so reaching this many
    # pages means Intercom started paginating on its own and the read is spending
    # more than the answer is worth.
    MAX_COLLECTED_PAGES = 10

    # `next_cursor` is nil as soon as Intercom stops advertising a next page, so
    # callers never have to know how the absence is spelled on the wire.
    # `total_count` is exact, filter included, which is what makes Forest's
    # record counter and its "number of" charts one request each.
    # `total_pages` is filled by the one endpoint that paginates by offset and
    # nil everywhere else: a cursor page has no notion of how many there are.
    Page = Struct.new(:records, :next_cursor, :total_count, :total_pages, keyword_init: true)

    def initialize(configuration)
      @configuration = configuration
      # Named per instance rather than per class: two datasources are two
      # workspaces, and a scope shared between them would hand one the other's
      # answer. A handful of clients live in a process, so a symbol each costs
      # nothing.
      @scope_key = :"forest_admin_datasource_intercom_read_scope_#{object_id}"
      # Both connections built here rather than memoized on first use. Neither
      # reaches the network -- and what a lazy reader would hand the thread
      # that lost the race is no longer a spare object but a pool of open
      # sockets, nothing left to close it. The adapter is resolved once for the
      # two of them.
      @adapter = resolve_adapter
      @connection = build_connection(retry_policy: @configuration.retry_policy,
                                     timeout: @configuration.timeout,
                                     open_timeout: @configuration.open_timeout)
      # For what is read while the datasource is being constructed -- the
      # custom-attribute introspection above all: short timeouts and one quick
      # retry, so a slow Intercom cannot turn a Rails boot into minutes of
      # waiting. Built apart from the one above, which keeps the patience every
      # later request is entitled to.
      @boot_connection = build_connection(retry_policy: @configuration.boot_retry_policy,
                                          timeout: @configuration.boot_timeout,
                                          open_timeout: @configuration.boot_open_timeout)
    end

    # Deduplicates reads while one page is built (e.g. ticket contacts read for a column and a relation).
    # Fiber-local (`Thread.current[]`) so concurrent requests on a fiber scheduler never share a scope;
    # re-entrant; callers share returned objects, which must not be mutated.
    def with_read_scope
      return yield unless Thread.current[@scope_key].nil?

      Thread.current[@scope_key] = {}
      begin
        yield
      ensure
        Thread.current[@scope_key] = nil
      end
    end

    # Health check: the admin the token belongs to, plus its workspace. Enough
    # to prove the credentials are usable, and the one call that verifies the
    # pinned API version was honoured -- Intercom echoes the version it served
    # in a response header.
    #
    # `boot: true` runs it on the short-timeout connection, for a caller
    # checking the token while the agent is still starting.
    def me(boot: false)
      must_succeed('me') do
        response = get('me', boot: boot)
        verify_pinned_version(response)
        response.body
      end
    end

    # `/tickets/search` answers under `tickets`, not `data` (measured), so the caller names its `list_key`.
    def list_page(path, per_page:, starting_after: nil, params: {}, list_key: 'data', boot: false)
      query = params.merge('per_page' => self.class.bounded_per_page(per_page))
      query['starting_after'] = starting_after unless blank?(starting_after)

      must_succeed(path) { to_page(get(path, query, boot: boot).body, path, list_key) }
    end

    # `params` stays in the query string (`display_as`). `sort` is honoured by `/contacts/search` alone:
    # the other search endpoints silently ignore it (measured).
    def search_page(path, query:, per_page:, starting_after: nil, list_key: 'data', params: {}, sort: nil)
      pagination = { 'per_page' => self.class.bounded_per_page(per_page) }
      pagination['starting_after'] = starting_after unless blank?(starting_after)
      body = { 'query' => query, 'pagination' => pagination }
      body['sort'] = sort_clause(sort) if sort

      within_read_scope(['search', path, body, params, list_key]) do
        must_succeed(path) { to_page(post(path, body, params: params).body, path, list_key) }
      end
    end

    # One page of an endpoint that paginates by **offset** rather than by
    # cursor. `POST /companies/list` is the only one, and it is what lets the
    # Companies collection answer page 7 of a list view with one request
    # instead of walking six pages to reach it. Intercom counts pages from 1.
    def offset_page(path, page:, per_page:, params: {}, list_key: 'data')
      query = params.merge('page' => [page.to_i, 1].max,
                           'per_page' => self.class.bounded_per_page(per_page))

      must_succeed(path) { to_offset_page(post(path, {}, params: query).body, path, list_key) }
    end

    # An exact lookup, and the shape surprise that comes with it: `GET
    # /companies?name=` answers the company itself where `?tag_id=` answers a
    # list. A record is read here as a page of one, so a caller writes one route
    # rather than testing the envelope.
    def lookup_page(path, params:, list_key: 'data')
      must_succeed(path) do
        body = get(path, params).body
        next Page.new(records: [body], next_cursor: nil, total_count: 1) if single_record?(body, list_key)

        to_page(body, path, list_key)
      end
    end

    # One record from its own endpoint. Raises on a 404 like on any other
    # failure: what a missing record means -- a stale link, a record outside the
    # token's scope, a deletion -- is the caller's to decide, not the client's.
    def fetch_record(path, id, params: {}, boot: false)
      within_read_scope(record_key(path, id, params)) { read_record(path, id, params, boot: boot) }
    end

    # Records read one request each, `concurrent_reads` at a time, in the order
    # of `ids`; nil for one Intercom no longer answers. The read scope is read
    # and written here, on the calling thread: a worker sees neither, a Hash
    # shared between threads being no store.
    def fetch_records(path, ids, params: {})
      scope = Thread.current[@scope_key]
      found = {}
      pending = []
      ids.uniq.each do |id|
        key = record_key(path, id, params)
        scope&.key?(key) ? found[id] = scope[key] : pending << id
      end

      read_concurrently(pending) { |id| record_or_nil(path, id, params) }.each do |id, record|
        found[id] = record
        scope[record_key(path, id, params)] = record if scope && record
      end
      ids.map { |id| found[id] }
    end

    # Every record of an unpaginated reference endpoint, held in `Cache` for the configured window.
    # A cursor is still followed defensively. `boot` only picks the connection, so it is not part of the key;
    # the list is frozen shallowly so no caller mutates what the next page reads.
    def fetch_all(path, list_key: 'data', params: {}, boot: false)
      @configuration.reference_cache.fetch(['fetch_all', path, list_key, params]) do
        must_succeed(path) do
          collect_pages(path, list_key: list_key, params: params, boot: boot).freeze
        end
      end
    end

    # The page size Intercom accepts, whatever was asked for.
    def self.bounded_per_page(size)
      value = size.to_i
      return 1 if value < 1

      [value, MAX_PER_PAGE].min
    end

    # The client holds the connections whose headers carry the access token in
    # clear, and Faraday prints those headers on `inspect`.
    def inspect
      "#<#{self.class.name} url=#{@configuration.redacted_url.inspect}>"
    end

    private

    # Readers rather than builders: both connections are built in the
    # constructor, where what distinguishes them is argued.
    attr_reader :connection, :boot_connection

    # The answer already given for `key` while this page was being built, or the
    # block's. Outside a scope -- a smart action, a boot read -- the block runs
    # as it always did: nothing is remembered where nothing opened a scope.
    #
    # A block that raises writes nothing, so a failed read is not replayed to
    # the rest of the page as an answer.
    def within_read_scope(key)
      scope = Thread.current[@scope_key]
      return yield if scope.nil?
      return scope[key] if scope.key?(key)

      scope[key] = yield
    end

    def record_key(path, id, params) = ['record', path, id, params]

    def read_record(path, id, params, boot: false)
      operation = "#{path}/#{id}"

      must_succeed(operation) do
        body = get("#{path}/#{Faraday::Utils.escape(id)}", params, boot: boot).body
        body.is_a?(Hash) ? body : refuse_body_shape(operation, 'the response is not a record')
      end
    end

    def record_or_nil(path, id, params)
      read_record(path, id, params)
    rescue APIError => e
      raise unless e.status == 404

      nil
    end

    # `items` mapped through the block, at most `concurrent_reads` at a time.
    # Inline at a width of one, which is the behaviour of before this existed.
    # Wider, a failure stops the workers taking new items, every worker is
    # joined, and the failure raised is the first in the order of `items` --
    # the same one whatever order the responses came back in.
    def read_concurrently(items, &read)
      width = [@configuration.concurrent_reads, items.size].min
      return items.to_h { |item| [item, yield(item)] } if width <= 1

      outcomes = run_workers(items, width, &read)
      failure = items.lazy.map { |item| outcomes[item] }.find { |outcome| outcome&.first == :error }
      raise failure.last if failure

      items.to_h { |item| [item, outcomes[item].last] }
    end

    def run_workers(items, width, &read)
      queue = Queue.new
      items.each { |item| queue << item }
      queue.close
      outcomes = {}
      lock = Mutex.new

      Array.new(width) do
        Thread.new do
          while (item = queue.pop)
            outcome = attempt(item, &read)
            lock.synchronize { outcomes[item] = outcome }
            queue.clear if outcome.first == :error
          end
        end
      end.each(&:join)
      outcomes
    end

    def attempt(item)
      [:ok, yield(item)]
    rescue StandardError => e
      [:error, e]
    end

    # The raw response rather than its body: the quota headers are read by the
    # throttle, and the version echo by `verify_pinned_version`.
    def get(path, params = nil, boot: false)
      (boot ? boot_connection : connection).get(path, params)
    end

    def post(path, body, params: {}, boot: false)
      http = boot ? boot_connection : connection

      http.post(path) do |request|
        request.params.update(params) unless params.nil? || params.empty?
        request.body = body
      end
    end

    # Intercom serves the version its workspace defaults to when the pin is not
    # honoured, and the payloads differ between versions. The echo is the only
    # way to notice, and noticing at boot is worth more than a schema that
    # drifts silently -- so this reports rather than raises: the agent still runs
    # against a version it did not ask for, which is better than not running.
    def verify_pinned_version(response)
      served = response.headers['intercom-version'] if response.respond_to?(:headers)
      return if served.nil? || served.to_s == @configuration.api_version

      ForestAdminDatasourceIntercom.logger.warn(
        "[forest_admin_datasource_intercom] asked Intercom for API version #{@configuration.api_version} " \
        "and it served #{served}. Payload shapes may differ from the ones this datasource expects; check the " \
        "workspace's default version in the Developer Hub."
      )
    end

    # Intercom spells an order `{ "field": "...", "order": "descending" }`,
    # and answers `data_invalid` on anything else -- so the clause is written
    # here rather than by the caller, whose vocabulary is Forest's.
    def sort_clause(sort)
      { 'field' => sort[:field].to_s, 'order' => sort[:ascending] == false ? 'descending' : 'ascending' }
    end

    # A record rather than a listing: no list under either key, and an id where
    # a record carries one. An empty listing is not one of these -- it answers
    # `data` as an empty array, which is a page of nothing rather than a record.
    def single_record?(body, list_key)
      body.is_a?(Hash) && !body[list_key].is_a?(Array) && !body['data'].is_a?(Array) && body.key?('id')
    end

    def collect_pages(path, list_key:, params:, boot:)
      records = []
      cursor = nil
      pages = 0

      loop do
        query = cursor.nil? ? params : params.merge('starting_after' => cursor)
        body = get(path, query.empty? ? nil : query, boot: boot).body
        records.concat(extract_entities(body, path, list_key))
        pages += 1
        cursor = next_cursor(body, path)
        break if cursor.nil?

        if pages >= MAX_COLLECTED_PAGES
          log_collection_cap(path, pages, records.size)
          break
        end
      end

      records
    end

    # The records under the key the endpoint uses, or under `data`. Anything
    # else is refused rather than read as an empty page: `Array()` would turn the
    # envelope into `[key, value]` pairs a collection would serialize into rows
    # holding nothing -- a page that looks answered and is empty -- and a
    # reference collection silently read as empty is a state column with no
    # values and an assignee shown as a raw id.
    def extract_entities(body, operation, list_key)
      return [] if body.nil? || body == ''

      entities = body.is_a?(Hash) ? (body[list_key] || body['data']) : nil
      return entities if entities.is_a?(Array)

      detail = list_key == 'data' ? "'data' is not a list" : "neither '#{list_key}' nor 'data' is a list"
      refuse_body_shape(operation, detail)
    end

    def log_collection_cap(path, pages, collected)
      ForestAdminDatasourceIntercom.logger.warn(
        "[forest_admin_datasource_intercom] Stopped reading #{path} after #{pages} page(s) / " \
        "#{collected} record(s); the rest is left out. This endpoint is read whole on purpose, so a workspace " \
        'this large needs the collection bounded rather than listed.'
      )
    end

    # Intercom wraps a listing in `{ "type": "list", "data": [...],
    # "total_count": N, "pages": { "next": { "starting_after": "..." } } }`.
    def to_page(body, operation, list_key)
      Page.new(records: extract_entities(body, operation, list_key),
               next_cursor: next_cursor(body, operation),
               total_count: extract_count(body),
               total_pages: extract_total_pages(body))
    end

    # The offset tier addresses the page after this one by number, and Intercom
    # advertises it the same way -- `pages.next` there is a page, not a cursor.
    # Reading it as one is what made the Companies list refuse a perfectly
    # ordinary answer, so this page is built without it.
    def to_offset_page(body, operation, list_key)
      Page.new(records: extract_entities(body, operation, list_key),
               next_cursor: nil,
               total_count: extract_count(body),
               total_pages: extract_total_pages(body))
    end

    # Absent on the last page. An older API version (served despite the pin) spells it as a url, so the
    # cursor is read from its query string; an unreadable advertised cursor is refused, not taken as the end.
    def next_cursor(body, operation)
      advertised = body.is_a?(Hash) && body['pages'].is_a?(Hash) ? body['pages']['next'] : nil
      return nil if advertised.nil?

      cursor = case advertised
               when Hash then advertised['starting_after']
               when String then cursor_from_url(advertised)
               end

      presence(cursor) || refuse_body_shape(operation, "'pages.next' carries no cursor this can follow")
    end

    def cursor_from_url(url)
      Faraday::Utils.parse_query(URI.parse(url).query.to_s)['starting_after']
    rescue URI::InvalidURIError
      nil
    end

    # nil rather than 0 when Intercom sends no count: zero is an answer, and
    # this is the absence of one.
    def extract_count(body)
      count = body['total_count'] if body.is_a?(Hash)
      count.is_a?(Numeric) ? count.to_i : nil
    end

    # How many pages the offset tier has to read through, when the endpoint
    # counts them. nil on a cursor page, which counts nothing.
    def extract_total_pages(body)
      pages = body['pages'] if body.is_a?(Hash)
      total = pages['total_pages'] if pages.is_a?(Hash)
      total.is_a?(Numeric) ? total.to_i : nil
    end

    def refuse_body_shape(operation, detail)
      raise APIError.new("Intercom API call failed: #{operation}: unexpected response shape, #{detail}", status: nil)
    end

    def presence(value)
      blank?(value) ? nil : value
    end

    def blank?(value)
      value.nil? || value.to_s.empty?
    end

    # `cause: nil`: the chained original would quote the payload, the URL, or the request with its bearer token.
    def must_succeed(operation)
      yield
    rescue Faraday::Error, JSON::ParserError => e
      raise api_error(operation, e), cause: nil
    rescue APIError
      # Already mapped, with its status intact; re-wrapping would erase it --
      # a 404 read as "no such record" rather than as a failure, above all.
      raise
    rescue StandardError => e
      raise APIError, "Intercom API call failed: #{operation}: #{e.class}: #{e.message}", cause: nil
    end

    # Builds an APIError preserving the HTTP status and Intercom's own error body
    # so a smart action can show the operator the real reason instead of
    # "failed".
    def api_error(operation, error)
      response = response_of(error)
      status = response[:status]
      body   = parse_body(response[:body])

      APIError.new("Intercom API call failed: #{operation}: #{failure_detail(error, status, body)}",
                   status: status, body: body)
    end

    # Faraday hands the status and the body back in a plain hash on most errors
    # and in its own `Env` on a parsing error; both answer `[]`.
    def response_of(error)
      response = error.respond_to?(:response) ? error.response : nil
      return { status: nil, body: nil } unless response.respond_to?(:[])

      { status: response[:status], body: response[:body] }
    end

    # A body that could not be parsed is named, never quoted: the parser's own
    # message opens with the characters it choked on, and on a 200 those are the
    # payload -- a conversation body, most of the time (R10).
    def failure_detail(error, status, body)
      return unreadable_detail(status) if parse_failure?(error)
      return "#{error.class}: #{error.message}" unless status

      "HTTP #{status} #{error_message(body)}".strip
    end

    def unreadable_detail(status)
      detail = 'the response could not be read as JSON'
      status ? "#{detail} (HTTP #{status})" : detail
    end

    def parse_failure?(error)
      error.is_a?(Faraday::ParsingError) || error.is_a?(JSON::ParserError)
    end

    # The request id is appended after truncation since Intercom support asks for it. A non-error body is
    # never echoed -- it may be a payload such as a conversation body (R10); only its size is reported.
    def error_message(parsed)
      return "(unreadable body, #{parsed.to_s.bytesize} bytes)" unless parsed.is_a?(Hash)

      message = join_errors(parsed['errors'])
      message = parsed.to_json if message.empty?

      append_request_id(message[0, 500], parsed['request_id'])
    end

    def join_errors(errors)
      Array(errors).filter_map do |error|
        next error unless error.is_a?(Hash)

        [error['code'], error['message']].compact.join(': ')
      end.join('; ')
    end

    def append_request_id(message, request_id)
      return message unless request_id

      "#{message} (request_id: #{request_id})"
    end

    def parse_body(body)
      return body unless body.is_a?(String) && !body.empty?

      JSON.parse(body)
    rescue JSON::ParserError
      body
    end

    # Resolved once, at boot: an adapter this process cannot load is refused
    # there rather than on the first request. The persistent adapter registers
    # itself only once its gem is required.
    def resolve_adapter
      name, options = Array(@configuration.adapter || Configuration::DEFAULT_ADAPTER)
      require 'faraday/net_http_persistent' if name == :net_http_persistent
      Faraday::Adapter.lookup_middleware(name)

      [name, options || {}]
    rescue LoadError, Faraday::Error
      raise ConfigurationError,
            "ForestAdminDatasourceIntercom adapter #{name.inspect} cannot be loaded by this process. Add the gem " \
            'that provides it, or set an adapter this process can load.'
    end

    # `raise_error` outside the JSON parser (raises with a parsed body); `retry` innermost to see raw 429s;
    # the throttle inside `retry` so replays wait and 429 headers reach the one shared limiter.
    def build_connection(retry_policy:, timeout:, open_timeout:)
      name, options = @adapter

      Faraday.new(url: @configuration.url) do |f|
        f.request :json
        f.response :raise_error
        f.response :json
        f.request :retry, **retry_policy.to_faraday_options
        f.use Throttle, limiter: @configuration.rate_limiter if @configuration.rate_limiter
        f.adapter(name, **options)
        f.headers['Authorization'] = "Bearer #{@configuration.access_token}"
        f.headers['Accept'] = 'application/json'
        f.headers['Intercom-Version'] = @configuration.api_version
        f.headers['User-Agent'] = "forest_admin_datasource_intercom/#{VERSION}"
        f.options.open_timeout = open_timeout
        f.options.timeout = timeout
      end
    end
  end
end
