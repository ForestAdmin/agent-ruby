module ForestAdminDatasourcePylon
  # Everything governing how the client reacts to a failed request, in one
  # place: which statuses and exceptions are worth another attempt, on which
  # verbs, and how long to wait.
  class RetryPolicy
    # Pylon quotas are per-minute, so a 429 routinely carries a Retry-After of up
    # to 60s. faraday-retry gives up outright when Retry-After exceeds
    # max_interval (`return if retry_after > max_interval`), so the cap has to
    # cover a full rate-limit window or the 429 retry never fires when it matters.
    DEFAULT_MAX_INTERVAL = 65

    STATUSES = [429, 502, 503, 504].freeze

    # faraday-retry's defaults plus ConnectionFailed: a dropped connection is
    # exactly the transient failure a resilient client should absorb, and it is
    # not retried out of the box.
    EXCEPTIONS = [
      Errno::ETIMEDOUT, 'Timeout::Error', Faraday::TimeoutError,
      Faraday::RetriableResponse, Faraday::ConnectionFailed
    ].freeze

    # Faraday only retries these by default; a 429 is safe to retry on any verb
    # because Pylon rejected the request before processing it, whereas a 502 on a
    # POST /issues may well have created the issue. This has to go through
    # retry_if rather than methods: faraday-retry ORs the two, so methods can
    # only widen the set, never restrict it.
    IDEMPOTENT_METHODS = %i[delete get head options put].freeze
    RETRY_IF = ->(env, _exception) { env[:status] == 429 }

    BACKOFF_FACTOR = 2

    attr_reader :max_retries, :interval, :max_interval

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
        methods: IDEMPOTENT_METHODS,
        retry_if: RETRY_IF
      }
    end
  end
end
