module ForestAdminDatasourceIntercom
  # TTL store for workspace reference reads (teammates, teams, ticket types, ticket states), re-read
  # on every page otherwise. Records are never cached here; see `Client#with_read_scope` for per-page dedup.
  class Cache
    Entry = Struct.new(:value, :expires_at)

    # Monotonic rather than wall clock: this measures an elapsed span, and a
    # host whose clock steps -- an NTP correction, a suspend -- would otherwise
    # expire every entry at once or hold them all far past the window.
    def initialize(ttl:, now: nil)
      @ttl = ttl.to_f
      @now = now || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      @mutex = Mutex.new
      @entries = {}
      # Bumped by `clear`, and carried by every read that is about to fetch, so
      # a response already in flight when the store was dropped cannot land in
      # it afterwards. See `fetch`.
      @generation = 0
    end

    def enabled? = @ttl.positive?

    # The block runs outside the mutex (it is an HTTP request): two concurrent misses both read, which is
    # cheaper than serializing every thread. A raising block writes nothing, and the generation is read
    # before the block so a response in flight across `clear` is not stored.
    def fetch(key)
      return yield unless enabled?

      hit = read(key)
      return hit.value if hit

      generation = @mutex.synchronize { @generation }
      value = yield
      write(key, value, generation)
      value
    end

    # Drops everything held, without waiting the window out. Nothing inside this
    # package calls it: the window is what expires an entry, and no read here
    # writes. It is reachable through `Configuration#reference_cache` for the
    # one case the window cannot serve -- a customizer that has just written a
    # team or a ticket type into the workspace and wants the next page to show
    # it. Documented in the README beside the ttl.
    def clear
      @mutex.synchronize do
        @entries.clear
        @generation += 1
      end
    end

    private

    def read(key)
      @mutex.synchronize do
        entry = @entries[key]
        next nil if entry.nil?

        if entry.expires_at <= @now.call
          @entries.delete(key)
          next nil
        end

        entry
      end
    end

    # Expired entries are dropped on the way past rather than by a sweeper: the
    # keys are a handful of endpoints, so the walk is short and there is no
    # thread to own.
    #
    # A write from before a `clear` is dropped rather than stored: the store it
    # was going to land in no longer exists.
    def write(key, value, generation)
      now = @now.call

      @mutex.synchronize do
        next if generation != @generation

        @entries.delete_if { |_, entry| entry.expires_at <= now }
        @entries[key] = Entry.new(value, now + @ttl)
      end
    end
  end
end
