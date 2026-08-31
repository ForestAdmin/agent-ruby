module ForestAdminDatasourceIntercom
  # Paces requests on what Intercom says is left of the current window, so the
  # budget is spent rather than exceeded.
  #
  # Intercom meters the app and, above it, the whole workspace -- 25 000
  # requests a minute shared with every other private app the customer runs --
  # and it allocates that budget in 10-second windows: the measured
  # `x-ratelimit-limit` is 1667, not 10 000. A burst of 3 000 requests in two
  # seconds therefore takes a 429 while the minute's budget is barely touched,
  # which is why what matters here is the instantaneous rate and not a volume
  # per minute.
  #
  # Unlike an API that only documents its budgets, Intercom reports the state of
  # the window on every response, so this is driven by those headers rather than
  # by a table: what is left, and when it refills. This sits in front of the 429
  # retry rather than replacing it -- the retry stays the backstop for the part
  # of the workspace budget spent by traffic this process never sees.
  #
  # One limiter per Configuration, hence per token, since that is what Intercom
  # meters.
  class RateLimiter
    # Intercom's allocation window. Only used as the ceiling below: the reset
    # instant itself always comes from the response.
    WINDOW = 10.0

    # How far past the reset a request may be held. A little over one window, so
    # a full window can be waited out, and no more: past this the wait is not
    # Intercom's window emptying but a clock disagreeing.
    DEFAULT_MAX_WAIT = 12.0

    attr_reader :max_wait

    def initialize(max_wait: DEFAULT_MAX_WAIT, now: nil, sleeper: nil)
      @max_wait = max_wait.to_f
      # Wall clock rather than monotonic on purpose: `X-RateLimit-Reset` is an
      # absolute epoch second on Intercom's clock, so the two have to be
      # comparable. `clamp_wait` is what keeps a skewed clock from turning that
      # comparison into a long sleep.
      @now      = now || -> { Time.now.to_f }
      @sleeper  = sleeper || ->(seconds) { sleep(seconds) }
      @mutex    = Mutex.new
      @remaining = nil
      @reset_at  = nil
      @limit     = nil
      @warned_at = nil
    end

    # Blocks until the current window has room, then returns. Called once per
    # attempt, retries included: a replayed request spends the budget a first
    # one did.
    def acquire
      wait, declined = @mutex.synchronize { plan_wait }

      warn_saturated(declined) if declined
      return if wait <= 0

      @sleeper.call(wait)
    end

    # What a response says about the window it was answered in. Called on every
    # response, the 429 included -- that one carries the most useful reset of
    # all.
    def observe(headers)
      limit     = integer_header(headers, 'x-ratelimit-limit')
      remaining = integer_header(headers, 'x-ratelimit-remaining')
      reset_at  = integer_header(headers, 'x-ratelimit-reset')
      return if remaining.nil? && reset_at.nil?

      @mutex.synchronize { record(limit, remaining, reset_at) }
    end

    private

    # A local decrement per request on top of what the headers report: several
    # requests can be in flight before any of them comes back, and a `remaining`
    # that only ever moves on a response lets all of them through on the same
    # stale figure.
    #
    # Returns the wait the caller owes and, when the reset is too far out to be
    # waited for, the wait that was declined -- nil otherwise. Both are settled
    # here, the second reading shared state like the first: it is nil on every
    # bypass but the first of a window, so the log line is not repeated.
    def plan_wait
      @remaining -= 1 if @remaining
      return [0, nil] unless exhausted?

      wait = clamp_wait(@reset_at - @now.call)
      return [0, nil] if wait <= 0
      return [0, first_warning? ? wait : nil] if wait > @max_wait

      [wait, nil]
    end

    # Nothing left in a window that has not refilled yet. An unknown state --
    # before the first response -- is not exhaustion: the first request is what
    # discovers the budget.
    def exhausted?
      !@remaining.nil? && @remaining <= 0 && !@reset_at.nil?
    end

    # Intercom's reset is a timestamp from its clock, and the two clocks can
    # disagree by more than the window is long. A wait longer than a window plus
    # its own slack is that disagreement rather than a window emptying, so it is
    # cut back to something a caller can afford to wait.
    def clamp_wait(seconds)
      return 0.0 if seconds <= 0

      [seconds, WINDOW + @max_wait].min
    end

    # A window is adopted whole. A response answered in an older window than the
    # one already recorded is ignored: replies come back out of order, and one
    # from the previous window would otherwise resurrect a budget already spent.
    #
    # Within the same window the smaller `remaining` wins, so the local
    # decrements of in-flight requests are not undone by a response that left
    # Intercom before they were made.
    def record(limit, remaining, reset_at)
      return if reset_at && @reset_at && reset_at < @reset_at

      new_window = reset_at && (@reset_at.nil? || reset_at > @reset_at)
      @reset_at  = reset_at if reset_at
      @limit     = limit if limit
      return if remaining.nil?

      @remaining = new_window || @remaining.nil? ? remaining : [remaining, @remaining].min
    end

    # One line per window. What the warning reports is a saturation that lasts,
    # so a line per request puts one on every request it describes -- hundreds
    # of them, burying the first, which is the only one the operator needed.
    def first_warning?
      now = @now.call
      return false if @warned_at && now - @warned_at < WINDOW

      @warned_at = now
      true
    end

    def warn_saturated(wait)
      ForestAdminDatasourceIntercom.logger.warn(
        "[forest_admin_datasource_intercom] the Intercom rate-limit window is spent (limit #{@limit || "unknown"} " \
        "per #{WINDOW.round}s) and its reset is #{wait.round(1)}s out, past the #{@max_wait.round(1)}s this waits. " \
        'Letting the request through -- Intercom may answer 429, which the client retries. A reset this far out ' \
        "usually means this host's clock disagrees with Intercom's. Reported once per #{WINDOW.round}s."
      )
    end

    def integer_header(headers, name)
      value = header_value(headers, name)
      return nil if value.nil? || value.to_s.strip.empty?

      Integer(value.to_s.strip, exception: false)
    end

    # Faraday hands over headers that look themselves up case-insensitively, but
    # what reaches here is whatever the middleware was given -- a plain hash
    # included -- and HTTP header names are case-insensitive on the wire.
    def header_value(headers, name)
      return nil if headers.nil?

      direct = headers[name]
      return direct unless direct.nil?
      return nil unless headers.respond_to?(:find)

      headers.find { |key, _value| key.to_s.downcase == name }&.last
    end
  end
end
