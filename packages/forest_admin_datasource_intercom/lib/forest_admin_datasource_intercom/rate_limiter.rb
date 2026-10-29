module ForestAdminDatasourceIntercom
  # Paces on Intercom's x-ratelimit-* headers. Workspace budget is 25 000/min but allocated in 10s windows
  # (measured x-ratelimit-limit 1667), so the instantaneous rate matters. Paces, does not queue: callers
  # woken at a reset can burst unmetered until the next response; the 429 retry behind this absorbs it.
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

    # Decrements locally so in-flight requests do not all pass on the same stale `remaining`; a
    # `remaining` of 1 still allows this request. The declined wait is returned only once per window.
    def plan_wait
      unless exhausted?
        @remaining -= 1 if @remaining
        return [0, nil]
      end

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
