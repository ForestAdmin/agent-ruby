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

    # The verbs that change nothing, so any transient failure is worth another
    # attempt. Narrower than faraday-retry's idempotent default: a 502 or a
    # dropped connection on the way back from a DELETE Pylon did perform is
    # replayed into a 404, which the write path then surfaces as a deletion that
    # failed when it landed.
    #
    # A 429 stays safe to retry on any verb, Pylon having rejected the request
    # before processing it, and travels through retry_if rather than through this
    # list: faraday-retry ORs the two, so methods can only widen the set, never
    # restrict it.
    RETRYABLE_METHODS = %i[get head options].freeze
    RETRY_IF = ->(env, _exception) { env[:status] == 429 }

    # The cap for a call that must not hold the boot, deliberately below a
    # rate-limit window where DEFAULT_MAX_INTERVAL sits above it: a Retry-After
    # past the cap makes faraday-retry abandon outright, which is what turns a
    # 429 into an immediate give-up rather than a minute of waiting per attempt.
    BOOT_MAX_INTERVAL = 2

    BACKOFF_FACTOR = 2

    attr_reader :max_retries, :interval, :max_interval

    # One retry rather than none, for what is read once and never revisited: a
    # transient failure there costs its result for the whole life of the process,
    # and half a second absorbs the hiccup without waiting a 429 out.
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
