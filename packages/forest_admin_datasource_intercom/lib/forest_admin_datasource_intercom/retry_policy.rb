module ForestAdminDatasourceIntercom
  # Everything governing how the client reacts to a failed request, in one
  # place: which statuses and exceptions are worth another attempt, on which
  # verbs, and how long to wait.
  class RetryPolicy
    # Intercom allocates its quota in 10-second windows, so a 429 is recovered
    # from within one of them -- unlike an API metering by the minute. The cap
    # still has to cover a whole window: faraday-retry gives up outright when
    # Retry-After exceeds max_interval, which would turn the 429 retry into an
    # immediate give-up exactly when it matters.
    DEFAULT_MAX_INTERVAL = 12

    STATUSES = [429, 500, 502, 503, 504].freeze

    # Named rather than referenced: the persistent adapter is a gem the client
    # treats as optional -- it falls back to Faraday's default when the process
    # cannot load it -- so this file cannot name the class outright. Both places
    # that need it resolve it at the moment they are asked, and answer that it
    # cannot have been raised when nothing defined it.
    PERSISTENT_ADAPTER_ERROR = 'Net::HTTP::Persistent::Error'.freeze

    # faraday-retry's defaults plus ConnectionFailed, and the persistent adapter's own error, which it
    # re-raises unwrapped for messages it does not translate.
    EXCEPTIONS = [
      Errno::ETIMEDOUT, 'Timeout::Error', Faraday::TimeoutError,
      Faraday::RetriableResponse, Faraday::ConnectionFailed,
      PERSISTENT_ADAPTER_ERROR
    ].freeze

    # The verbs that change nothing, so any transient failure is worth another
    # attempt. Narrower than faraday-retry's idempotent default: a 502 or a
    # dropped connection on the way back from a POST Intercom did perform would
    # be replayed into a second reply on the conversation, or a second ticket.
    RETRYABLE_METHODS = %i[get head options].freeze

    # The paths Intercom answers a *read* on through POST: its three search
    # endpoints, and the one listing that paginates by offset. Nothing that
    # writes is spelled this way -- a reply is `POST /conversations/{id}/reply`,
    # a ticket `POST /tickets` -- so the exemption below cannot reach one.
    READ_ONLY_POST_PATHS = %r{/(search|list)\z}

    # Widens `methods` (ORed by faraday-retry) to a 429 on any verb, and to a dropped connection on a
    # read-only POST -- keep-alive makes an idle socket closed by the server an ordinary failure.
    RETRY_IF = lambda do |env, exception|
      env[:status] == 429 || (RetryPolicy.connection_failure?(exception) &&
                              READ_ONLY_POST_PATHS.match?(env[:url]&.path.to_s))
    end

    # Whether another attempt would be dialling again rather than re-sending.
    # See `PERSISTENT_ADAPTER_ERROR` for why one of the two is named.
    def self.connection_failure?(exception)
      return true if exception.is_a?(Faraday::ConnectionFailed)
      return false unless Object.const_defined?(PERSISTENT_ADAPTER_ERROR)

      exception.is_a?(Object.const_get(PERSISTENT_ADAPTER_ERROR))
    end

    # The cap for a call that must not hold the boot, deliberately below a
    # rate-limit window where DEFAULT_MAX_INTERVAL sits above it: a Retry-After
    # past the cap makes faraday-retry abandon outright, which is what turns a
    # 429 at boot into an immediate give-up rather than a window of waiting per
    # attempt.
    BOOT_MAX_INTERVAL = 2

    BACKOFF_FACTOR = 2

    attr_reader :max_retries, :interval, :max_interval

    # One retry rather than none, for what is read once and never revisited: a
    # transient failure there costs its result for the whole life of the
    # process, and half a second absorbs the hiccup without waiting a 429 out.
    def self.boot
      new(max_retries: 1, interval: 0.5, max_interval: BOOT_MAX_INTERVAL)
    end

    def initialize(max_retries: 3, interval: 0.5, max_interval: DEFAULT_MAX_INTERVAL)
      @max_retries  = max_retries
      @interval     = interval
      @max_interval = max_interval
    end

    def to_faraday_options
      {
        max: @max_retries,
        interval: @interval,
        max_interval: @max_interval,
        backoff_factor: BACKOFF_FACTOR,
        retry_statuses: STATUSES,
        exceptions: EXCEPTIONS,
        methods: RETRYABLE_METHODS,
        retry_if: RETRY_IF
      }
    end
  end
end
