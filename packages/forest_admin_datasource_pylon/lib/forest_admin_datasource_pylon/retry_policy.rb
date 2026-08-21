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

    # The verbs a replay cannot repeat: a GET, a HEAD and an OPTIONS change
    # nothing, so any transient failure is worth another attempt.
    #
    # DELETE is deliberately out, although HTTP calls it idempotent and
    # faraday-retry ships it as a default: a 502 or a dropped connection on the
    # way back from a DELETE Pylon did perform is replayed into a 404, which the
    # write path then surfaces as a deletion that failed when it landed -- the
    # very report of something that did not happen this datasource refuses. PUT
    # is out for having no endpoint: Pylon writes through POST and PATCH.
    #
    # A 429 stays safe to retry on any verb, Pylon having rejected the request
    # before processing it, and travels through retry_if rather than through this
    # list: faraday-retry ORs the two, so methods can only widen the set, never
    # restrict it.
    IDEMPOTENT_METHODS = %i[get head options].freeze
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
