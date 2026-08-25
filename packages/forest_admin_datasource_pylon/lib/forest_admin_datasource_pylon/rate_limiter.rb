module ForestAdminDatasourcePylon
  # Spaces requests out so the budget of an endpoint is spent rather than
  # exceeded: a sliding window per endpoint, and a wait until the next slot when
  # the window is full.
  #
  # This sits in front of the 429 retry rather than replacing it. The retry
  # answers a 429 Pylon already sent, which costs a full rate-limit window to
  # recover from (Retry-After runs up to 60s); waiting half a second for a slot
  # is the same throughput at a fraction of the latency. The retry stays as the
  # backstop for what this cannot see — another process, or another agent, on
  # the same token.
  #
  # One limiter per Configuration, so per token: Pylon meters the token, and two
  # agents holding different ones do not share a budget.
  class RateLimiter
    WINDOW = 60.0

    # How long one attempt may be held back before it is let through anyway. The
    # limiter exists to avoid a 429, not to guarantee one never happens: past
    # this point the window is saturated by more than this agent's own traffic,
    # so queueing behind it would trade a retry the client already handles for a
    # request the operator watches spin. It goes out, and the warning says why.
    #
    # Per attempt, not per request: `retry` replays up to `max_retries` times and
    # each replay asks for a slot of its own, so a request can spend this bound
    # once per attempt, on top of the backoff `retry` waits itself. None of it
    # runs under the Faraday timeout, which only covers the adapter.
    #
    # The region this smooths is narrow, and it is worth being plain about it.
    # On a stream over budget the waits accumulate rather than settling, so the
    # bound is crossed sooner the further over it sits: measured against a
    # 120/min endpoint, a stream 1% over budget throttles its first thousand
    # requests and then lets roughly one in twelve through unthrottled, one 5%
    # over gives up after two hundred and lets half through, and past ~10% over
    # the bound is crossed as soon as the window fills — request 121 — after
    # which almost nothing is throttled at all. A burst arriving at once books
    # its next slot a whole window out and goes straight through from the first
    # request past the budget. Under real saturation the 429 retry is the
    # defence, not this; what this buys is the region just over budget, and a
    # budget the code knows rather than one it discovers as a 429.
    DEFAULT_MAX_WAIT = 5.0

    attr_reader :max_wait, :window

    def initialize(limits: RateLimits, window: WINDOW, max_wait: DEFAULT_MAX_WAIT, clock: nil, sleeper: nil)
      @limits  = limits
      @window  = window.to_f
      @max_wait = max_wait.to_f
      @clock   = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      @sleeper = sleeper || ->(seconds) { sleep(seconds) }
      @mutex   = Mutex.new
      @slots   = {}
      @warned  = {}
    end

    # Blocks until the endpoint has room, then returns. Called once per attempt,
    # retries included: a replayed request spends the budget a first one did.
    def acquire(method, path)
      rule = @limits.for(method, path)
      wait, warn = @mutex.synchronize { reserve(rule) }

      warn_saturated(rule, wait) if warn
      return if wait <= 0 || wait > @max_wait

      @sleeper.call(wait)
    end

    private

    # The reservation happens under the lock and the waiting outside it: holding
    # the mutex across the sleep would serialize every thread behind the slowest
    # one, and threads waiting on unrelated endpoints have no reason to queue.
    #
    # What is recorded is the moment the request will be made, not the moment it
    # was asked for, so concurrent callers each take a distinct slot and spread
    # out instead of all waking onto the same one.
    #
    # Returns the wait the caller owes and whether this is the bypass worth a log
    # line — both settled here, the second being shared state like the first.
    def reserve(rule)
      taken = (@slots[rule.name] ||= [])
      now   = @clock.call
      expire(taken, now)

      slot   = next_slot(taken, rule.limit, now)
      wait   = slot - now
      bypass = wait > @max_wait
      # Past the bound the request goes out now, so the slot it books is now:
      # recording the one it declined to wait for would meter a request nobody
      # ever made and push the whole window further out.
      insert(taken, bypass ? now : slot)

      [wait, bypass && first_warning?(rule, now)]
    end

    # The bookings that have left the window are its leading run, the list being
    # kept ordered.
    def expire(taken, now)
      taken.shift(taken.bsearch_index { |at| at > now - @window } || taken.size)
    end

    # Now while the window still has room, otherwise a window past the limit-th
    # most recent booking, which is the one that has to fall out of it first —
    # an index that only reads as such on an ordered list.
    def next_slot(taken, limit, now)
      return now if taken.size < limit

      taken[taken.size - limit] + @window
    end

    # A booking has one position in an ordered list, so it goes there rather than
    # onto the end followed by a sort: `now` lands before the slots already
    # reserved further out, and the list is what `next_slot` reads an index off.
    def insert(taken, booking)
      taken.insert(taken.bsearch_index { |at| at >= booking } || taken.size, booking)
    end

    # One line per endpoint per window. What the warning reports is a saturation
    # that lasts, so a line per request puts one on every request it describes —
    # a thousand of them for a couple of minutes over budget, burying the first,
    # which is the only one the operator needed.
    def first_warning?(rule, now)
      last = @warned[rule.name]
      return false if last && now - last < @window

      @warned[rule.name] = now
      true
    end

    def warn_saturated(rule, wait)
      ForestAdminDatasourcePylon.logger.warn(
        "[forest_admin_datasource_pylon] #{rule.name} is at its budget of #{rule.limit} requests per " \
        "#{@window.round}s; the next slot is #{wait.round(1)}s out, past the #{@max_wait.round(1)}s this waits. " \
        'Letting the request through — Pylon may answer 429, which the client retries. Further requests over ' \
        "this budget are let through too, and this says so once per #{@window.round}s."
      )
    end
  end
end
