module ForestAdminDatasourceIntercom
  # A time-bounded store for what Intercom answers about the *workspace* rather
  # than about its records: the teammates, the teams, the ticket types and the
  # ticket states -- the tier `FetchAllCollection` reads whole.
  #
  # Those four endpoints are what makes a relation affordable, and they are
  # re-read on every page: a ticket list projecting `admin_assignee:name`,
  # `team_assignee:name`, `state:internal_label` and `ticket_type:name` spends
  # four sequential round trips on lists that change a few times a year, and
  # spends them again on the next page, on the count, and on every filter
  # traversing one of those relations.
  #
  # What the TTL buys is bounded staleness rather than none: a teammate added
  # while an operator is browsing shows up within the window instead of on the
  # next request. That is the trade the default is set for -- a minute of
  # staleness on a list of teams, against four round trips per page. A ttl of
  # zero takes the store out of the stack entirely, which is what a deployment
  # that would rather pay the requests sets.
  #
  # **Records are never cached here.** What a collection reads through the
  # search or the listing endpoints is the customer's data, and serving a page
  # of it from a store would show an operator a row they have just edited in
  # its previous state. See `Client#with_read_scope` for the other half of the
  # problem -- the same read issued twice while a single page is being built,
  # which is deduplicated for the duration of that page and not one instant
  # longer.
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
    end

    def enabled? = @ttl.positive?

    # The value for `key`, from the store or from the block.
    #
    # The block runs **outside** the mutex, deliberately: it performs an HTTP
    # request, and holding the lock across it would make every thread of the
    # process queue behind the first one to miss. The cost is that two threads
    # missing at once both read, and the second write wins -- a duplicated
    # request where a lock would have saved one, which is the cheaper of the two
    # failures by a wide margin.
    #
    # A block that raises writes nothing: a failure is not an answer, and
    # caching one would keep an outage alive for the length of the window.
    def fetch(key)
      return yield unless enabled?

      hit = read(key)
      return hit.value if hit

      value = yield
      write(key, value)
      value
    end

    # Drops everything held, without waiting the window out. Nothing inside this
    # package calls it: the window is what expires an entry, and no read here
    # writes. It is reachable through `Configuration#reference_cache` for the
    # one case the window cannot serve -- a customizer that has just written a
    # team or a ticket type into the workspace and wants the next page to show
    # it. Documented in the README beside the ttl.
    def clear
      @mutex.synchronize { @entries.clear }
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
    def write(key, value)
      now = @now.call

      @mutex.synchronize do
        @entries.delete_if { |_, entry| entry.expires_at <= now }
        @entries[key] = Entry.new(value, now + @ttl)
      end
    end
  end
end
