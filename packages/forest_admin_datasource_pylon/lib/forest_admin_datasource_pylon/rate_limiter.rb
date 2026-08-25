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

    # How long a request may be held back before it is let through anyway. The
    # limiter exists to avoid a 429, not to guarantee one never happens: past
    # this point the window is saturated by more than this agent's own traffic,
    # so queueing behind it would trade a retry the client already handles for a
    # request the operator watches spin. It goes out, and the warning says why.
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
    end

    # Blocks until the endpoint has room, then returns. Called once per attempt,
    # retries included: a replayed request spends the budget a first one did.
    def acquire(method, path)
      rule = @limits.for(method, path)
      wait = @mutex.synchronize { reserve(rule) }
      return if wait <= 0

      return warn_saturated(rule, wait) if wait > @max_wait

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
    def reserve(rule)
      taken = (@slots[rule.name] ||= [])
      now = @clock.call
      taken.reject! { |at| at <= now - @window }

      slot = taken.size < rule.limit ? now : taken[taken.size - rule.limit] + @window
      wait = slot - now
      # Past the bound the request goes out now, so the slot it books is now:
      # recording the one it declined to wait for would meter a request nobody
      # ever made and push the whole window further out.
      taken << (wait > @max_wait ? now : slot)

      wait
    end

    def warn_saturated(rule, wait)
      ForestAdminDatasourcePylon.logger.warn(
        "[forest_admin_datasource_pylon] #{rule.name} is at its budget of #{rule.limit} requests per " \
        "#{@window.round}s; the next slot is #{wait.round(1)}s out, past the #{@max_wait.round(1)}s this waits. " \
        'Letting the request through — Pylon may answer 429, which the client retries.'
      )
    end
  end
end
