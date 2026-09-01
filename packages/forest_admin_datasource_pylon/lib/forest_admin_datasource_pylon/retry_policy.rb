module ForestAdminDatasourcePylon
  # Everything governing how the client reacts to a failed request, in one
  # place: which statuses and exceptions are worth another attempt, on which
  # verbs, and how long to wait.
  class RetryPolicy
    # What one attempt may be held back before the retry is abandoned instead.
    # faraday-retry gives up outright when Retry-After exceeds max_interval
    # (`return if retry_after > max_interval`), so this is also the bound on what
    # a 429 costs: past it the client raises at once rather than sleeping.
    #
    # A fifth of a Pylon window rather than the whole of it, on purpose. Pylon
    # quotas are per-minute, so a 429 carries a Retry-After of up to 60s, and
    # honouring it three times over parked the calling thread for three minutes
    # -- long after the Forest server timed out the request nobody will now read,
    # and multiplied by the 20 sequential calls a single list view may spend
    # (`MAX_ID_LOOKUPS`). The figure is what keeps the sleeps of one whole
    # request under a minute: `max_retries` waits of this, plus the
    # `RateLimiter::DEFAULT_MAX_WAIT` each of the four attempts may also pay.
    #
    # The trade, plainly: a Retry-After past this makes the 429 surface as an
    # error where it used to be waited out, which is most of them -- the value
    # being the remainder of the minute window. Absorbing them is `RateLimiter`'s
    # job, metering each endpoint inside its budget before Pylon has to answer
    # 429 at all; this retry is the backstop for the traffic the limiter cannot
    # see, and a backstop may cost less than what it protects.
    DEFAULT_MAX_INTERVAL = 12

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

    # The same mechanism as DEFAULT_MAX_INTERVAL, tightened for a call that must
    # not hold the boot: what a request may wait once the agent is serving is
    # more than an operator watching Rails come up should pay per object type.
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
