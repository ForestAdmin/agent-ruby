module ForestAdminDatasourceIntercom
  # Every call to Intercom goes through here. Hand-written on Faraday rather
  # than through the official `intercom` gem: that one maps the JSON onto
  # objects, and what this datasource needs is the parts it hides -- the raw
  # payload, because a custom attribute is a key nobody declared in advance;
  # the quota headers, because the pacing is driven by them; and Intercom's own
  # error body, because that text is what an operator reads when an action
  # fails.
  # Long by line count only: the public surface is one method per endpoint, and
  # the rest is the envelope and error handling every one of them shares.
  class Client # rubocop:disable Metrics/ClassLength
    # `per_page=200` is refused with `invalid_per_page` -- "must be an integer
    # between 0 and 150". There is no silent downgrade, so a page size is bounded
    # before it is sent or the list view breaks rather than shrinks.
    MAX_PER_PAGE = 150

    # `next_cursor` is nil as soon as Intercom stops advertising a next page, so
    # callers never have to know how the absence is spelled on the wire.
    # `total_count` is exact, filter included, which is what makes Forest's
    # record counter and its "number of" charts one request each.
    Page = Struct.new(:records, :next_cursor, :total_count, keyword_init: true)

    def initialize(configuration)
      @configuration = configuration
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

    # One page of a cursor-paginated listing. `starting_after` is what the
    # previous page advertised; nil asks for the first one.
    #
    # `CursorWalker` is what turns the offset/limit window a list view asks for
    # into a sequence of these.
    def list_page(path, per_page:, starting_after: nil, params: {}, boot: false)
      query = params.merge('per_page' => self.class.bounded_per_page(per_page))
      query['starting_after'] = starting_after unless blank?(starting_after)

      must_succeed(path) { to_page(get(path, query, boot: boot).body, path) }
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
      "#<#{self.class.name} url=#{@configuration.url.inspect}>"
    end

    private

    # The raw response rather than its body: the quota headers are read by the
    # throttle, and the version echo by `verify_pinned_version`.
    def get(path, params = nil, boot: false)
      (boot ? boot_connection : connection).get(path, params)
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

    # Intercom wraps a listing in `{ "type": "list", "data": [...],
    # "total_count": N, "pages": { "next": { "starting_after": "..." } } }`.
    def to_page(body, operation)
      Page.new(records: extract_list(body, operation),
               next_cursor: next_cursor(body, operation),
               total_count: extract_count(body))
    end

    # A listing whose `data` is absent or is not a list broke the contract. It
    # is refused rather than read as an empty page: `Array()` would turn the
    # envelope into `[key, value]` pairs the collection would serialize into
    # rows holding nothing -- a page that looks answered and is empty.
    def extract_list(body, operation)
      data = body.is_a?(Hash) ? body['data'] : nil
      return data if data.is_a?(Array)

      refuse_body_shape(operation, "'data' is not a list")
    end

    # Absent on the last page, which is how the walk knows it is done. An older
    # API version spells it as a url instead of an object -- and one can be
    # served despite the pin, which is what the version echo warns about -- so
    # the cursor is read out of its query string rather than the page being
    # taken for the last one.
    #
    # Anything else is refused, an advertised page whose cursor cannot be read
    # included: taking it for the last page would truncate the answer silently,
    # which is worse than a failure naming what it could not read.
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

    def refuse_body_shape(operation, detail)
      raise APIError.new("Intercom API call failed: #{operation}: unexpected response shape, #{detail}", status: nil)
    end

    def presence(value)
      blank?(value) ? nil : value
    end

    def blank?(value)
      value.nil? || value.to_s.empty?
    end

    def must_succeed(operation)
      yield
    rescue Faraday::Error => e
      raise api_error(operation, e)
    rescue APIError
      # Already mapped, with its status intact; re-wrapping would erase it --
      # a 404 read as "no such record" rather than as a failure, above all.
      raise
    rescue StandardError => e
      raise APIError, "Intercom API call failed: #{operation}: #{e.class}: #{e.message}"
    end

    # Builds an APIError preserving the HTTP status and Intercom's own error body
    # so a smart action can show the operator the real reason instead of
    # "failed".
    def api_error(operation, error)
      response = error.respond_to?(:response) ? error.response : nil
      status = response.is_a?(Hash) ? response[:status] : nil
      body   = parse_body(response.is_a?(Hash) ? response[:body] : nil)
      detail = status ? "HTTP #{status} #{error_message(body)}".strip : "#{error.class}: #{error.message}"

      APIError.new("Intercom API call failed: #{operation}: #{detail}", status: status, body: body)
    end

    # Intercom answers a failure with `{ "type": "error.list", "request_id":
    # "...", "errors": [{ "code": ..., "message": ... }] }`. The request id is
    # what its support asks for first, so it is appended after the truncation
    # rather than being what a long body pushes out.
    def error_message(parsed)
      return parsed.to_s[0, 500] unless parsed.is_a?(Hash)

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

    def connection
      @connection ||= build_connection(
        retry_policy: @configuration.retry_policy,
        timeout: @configuration.timeout,
        open_timeout: @configuration.open_timeout
      )
    end

    # For what is read while the datasource is being constructed -- the
    # custom-attribute introspection above all: short timeouts and one quick
    # retry, so a slow Intercom cannot turn a Rails boot into minutes of
    # waiting. Memoized separately from `connection`, which keeps the patience
    # every later request is entitled to.
    def boot_connection
      @boot_connection ||= build_connection(
        retry_policy: @configuration.boot_retry_policy,
        timeout: @configuration.boot_timeout,
        open_timeout: @configuration.boot_open_timeout
      )
    end

    # Middleware order is deliberate: `raise_error` sits outside the JSON parser
    # so it raises with an already-parsed body, and `retry` sits innermost so it
    # inspects raw statuses -- behind `raise_error` it would never see a 429.
    #
    # The throttle goes inside `retry`, which is what makes a replay wait for
    # the window like a first attempt, and what lets the 429's own headers reach
    # the limiter: outside it, the middleware would run once for a request that
    # reached Intercom three times.
    #
    # How long a request may take is the caller's to state; everything else is
    # the same on every connection this builds, the limiter included -- a second
    # limiter would meter in a window of its own and spend the budget twice.
    def build_connection(retry_policy:, timeout:, open_timeout:)
      Faraday.new(url: @configuration.url) do |f|
        f.request :json
        f.response :raise_error
        f.response :json
        f.request :retry, **retry_policy.to_faraday_options
        f.use Throttle, limiter: @configuration.rate_limiter if @configuration.rate_limiter
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
