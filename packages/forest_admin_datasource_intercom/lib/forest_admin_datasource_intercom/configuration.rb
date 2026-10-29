module ForestAdminDatasourceIntercom
  # Long by line count only: every option of the datasource is declared here
  # with the reason it has the default it has, and next to the check that
  # refuses the shapes it cannot mean. Splitting the checks off would put an
  # option and its meaning in two files.
  class Configuration # rubocop:disable Metrics/ClassLength
    # A workspace is hosted in one region and answers in that region only. The
    # host is therefore a configuration parameter rather than a constant:
    # `api.intercom.io` does route to the right region, but a customer under
    # GDPR wants its requests to reach the European host and nothing else.
    REGION_HOSTS = {
      us: 'https://api.intercom.io',
      eu: 'https://api.eu.intercom.io',
      au: 'https://api.au.intercom.io'
    }.freeze

    DEFAULT_REGION = :us

    # Where a cleartext base_url reaches nobody else's network, so the bearer
    # header crossing it in clear is not worth a word.
    LOOPBACK_HOSTS = %w[localhost 127.0.0.1 ::1 [::1] 0.0.0.0].freeze

    # Without an explicit version a request follows the workspace's own default,
    # which an operator can change on Intercom's side -- and the payloads change
    # shape under us. Pinned to what the spike ran against; 2.14 and 2.16 both
    # answered, and the response echoes the version back, so `Client#me`
    # verifies at boot that the pin was honoured.
    DEFAULT_API_VERSION = '2.16'.freeze

    # Reference lists are re-read on every page otherwise (four sequential round trips per ticket list);
    # a minute bounds staleness. `0` disables the store. Records are never cached -- see `Cache`.
    DEFAULT_REFERENCE_CACHE_TTL = 60

    # A ticket list is ~7 requests to one host, so keep-alive saves a TLS handshake each. The pool is sized
    # against the server's thread count (Puma default 5): a thread waiting >0.5s for a connection gets a
    # non-retried timeout blamed on Intercom. `adapter: :net_http` opts out; an unloadable adapter is refused.
    DEFAULT_ADAPTER = [:net_http_persistent, { pool_size: 25 }].freeze

    # How many records a read by id fetches at once -- a related list of
    # companies, a page of timelines -- Intercom answering those one request
    # each. One by default: every extra read in flight holds a connection of
    # the pool above, so widening this is the integrator's call, made against
    # `pool_size` and the server's thread count together.
    DEFAULT_CONCURRENT_READS = 1

    attr_reader :access_token, :region, :base_url, :api_version, :open_timeout, :timeout,
                :retry_policy, :rate_limiter, :boot_open_timeout, :boot_timeout, :boot_retry_policy,
                :reference_cache_ttl, :adapter, :reference_cache, :concurrent_reads

    # `rate_limiter: nil` leaves the 429 retry as the only rate-limit handling. The `boot_` trio governs
    # reads made while the datasource is constructed (attribute introspection), during the Rails boot.
    def initialize(access_token:, region: nil, base_url: nil, api_version: DEFAULT_API_VERSION,
                   open_timeout: 5, timeout: 30, retry_policy: RetryPolicy.new,
                   rate_limiter: RateLimiter.new, boot_open_timeout: 3, boot_timeout: 10,
                   boot_retry_policy: RetryPolicy.boot,
                   reference_cache_ttl: DEFAULT_REFERENCE_CACHE_TTL, adapter: nil,
                   concurrent_reads: DEFAULT_CONCURRENT_READS)
      @access_token = access_token
      @region       = (region || DEFAULT_REGION).to_s.downcase.to_sym
      @base_url     = base_url
      @api_version  = api_version.to_s
      @open_timeout = open_timeout
      @timeout      = timeout
      @retry_policy = retry_policy
      @rate_limiter = rate_limiter
      @boot_open_timeout = boot_open_timeout
      @boot_timeout      = boot_timeout
      @boot_retry_policy = boot_retry_policy
      @reference_cache_ttl = reference_cache_ttl
      @adapter = normalize_adapter(adapter)
      @concurrent_reads = concurrent_reads
      validate!
      # One store per Configuration, hence per token, like the rate limiter:
      # what it holds is a workspace's own lists, and two workspaces do not
      # share them. Built here rather than lazily -- a memoized reader would
      # hand two stores to the two threads that first raced for it, and one of
      # them would then write into a store nothing else reads.
      @reference_cache = Cache.new(ttl: @reference_cache_ttl)
    end

    # An explicit `base_url` wins over the region: it is what points the client
    # at a mock server or an egress proxy, neither of which is a region.
    def url
      @url ||= (@base_url || REGION_HOSTS.fetch(@region)).chomp('/')
    end

    # The url with any credentials in it masked. `URI` accepts them --
    # `https://user:pass@proxy/...` -- and the refusal that names such a url
    # would otherwise print a second secret exactly where this class keeps the
    # first one from going. A query string is masked whole for the same
    # reason: it is where a gateway takes its key. Read by `Client#inspect`
    # too, which prints the same url.
    def redacted_url
      @redacted_url ||= url.sub(%r{\A([a-zA-Z][\w+.-]*://)[^/@]*@}, '\1[FILTERED]@')
                           .sub(/\?.*\z/m, '?[FILTERED]')
    end

    # `access_token` is a bearer credential, and nothing prints a Configuration
    # on purpose: what reaches an `inspect` is a Rails error page, or a
    # `logger.debug` of something holding one. The default would put the token
    # in clear there. `Client` and `Datasource` mask their own for the same
    # reason -- together they cut every path from an object this package hands
    # out to the credential.
    def inspect
      "#<#{self.class.name} url=#{redacted_url.inspect} api_version=#{@api_version.inspect} " \
        'access_token=[FILTERED]>'
    end

    private

    def validate!
      raise ConfigurationError, 'ForestAdminDatasourceIntercom missing required config: access_token' if
        blank?(@access_token)

      validate_region!
      validate_base_url!
      raise ConfigurationError, 'ForestAdminDatasourceIntercom api_version cannot be empty' if blank?(@api_version)

      validate_reference_cache_ttl!
      validate_concurrent_reads!
    end

    def validate_concurrent_reads!
      return if @concurrent_reads.is_a?(Integer) && @concurrent_reads.positive?

      raise ConfigurationError,
            'ForestAdminDatasourceIntercom concurrent_reads must be a whole number of reads, one or more, got ' \
            "#{@concurrent_reads.inspect}"
    end

    # Refuses nil, non-numeric strings and Infinity rather than coercing them into a silent 0 (cache off)
    # or a never-expiring cache.
    def validate_reference_cache_ttl!
      return if @reference_cache_ttl.is_a?(Numeric) && @reference_cache_ttl.finite? &&
                !@reference_cache_ttl.negative?

      raise ConfigurationError,
            'ForestAdminDatasourceIntercom reference_cache_ttl must be a finite number of seconds, zero or ' \
            "more, got #{@reference_cache_ttl.inspect}"
    end

    # Faraday's adapter registry is keyed by symbol: a string name (as YAML hands over) silently lost
    # keep-alive. Whether the name resolves is left to the client, which falls back.
    def normalize_adapter(adapter)
      return nil if adapter.nil?

      name, options = adapter.is_a?(Array) ? adapter : [adapter, nil]
      refuse_adapter!(adapter) unless name.respond_to?(:to_sym)
      refuse_adapter!(adapter) unless options.nil? || namable_hash?(options)

      options.nil? ? name.to_sym : [name.to_sym, options.to_h { |key, value| [key.to_sym, value] }]
    end

    def namable_hash?(options)
      options.is_a?(Hash) && options.keys.all? { |key| key.respond_to?(:to_sym) }
    end

    def refuse_adapter!(adapter)
      raise ConfigurationError,
            'ForestAdminDatasourceIntercom adapter must be an adapter name or a [name, options] pair, got ' \
            "#{adapter.inspect}"
    end

    def validate_region!
      return if @base_url || REGION_HOSTS.key?(@region)

      raise ConfigurationError,
            "ForestAdminDatasourceIntercom unknown region #{@region.inspect}: " \
            "expected one of #{REGION_HOSTS.keys.map(&:inspect).join(", ")}, or an explicit base_url."
    end

    # A base url that is not absolute makes Faraday resolve every path against
    # the process's working directory instead of Intercom, which surfaces much
    # later as a connection failure naming nothing.
    def validate_base_url!
      return if @base_url.nil?

      uri = URI.parse(@base_url)
      refuse_credentials! if uri.userinfo
      return warn_cleartext!(uri) if uri.is_a?(URI::HTTP) && !blank?(uri.host)

      raise ConfigurationError,
            "ForestAdminDatasourceIntercom base_url must be an absolute http(s) url, got #{redacted_url.inspect}"
    rescue URI::InvalidURIError
      # Without the parser's error, whose message quotes the url unredacted.
      raise ConfigurationError,
            "ForestAdminDatasourceIntercom base_url is not a valid url: #{redacted_url.inspect}", cause: nil
    end

    # Faraday turns credentials in the url into a Basic `Authorization`
    # header, which the Intercom bearer token then replaces: they would be
    # dropped on every request without a word. An egress proxy takes its
    # credentials from `HTTPS_PROXY`, which Faraday sends as
    # `Proxy-Authorization` instead.
    def refuse_credentials!
      raise ConfigurationError,
            "ForestAdminDatasourceIntercom base_url #{redacted_url.inspect} carries credentials, which cannot " \
            'travel: the Authorization header carries the Intercom access token. For a credentialed egress ' \
            'proxy, set HTTPS_PROXY=https://user:password@proxy:port instead.'
    end

    # `URI::HTTPS` is a `URI::HTTP`, so plain http passes above -- and it is
    # worth passing: a mock server in a test suite is one, and that is half of
    # what `base_url` is for. What it costs is `Authorization: Bearer <token>`
    # travelling in clear to whatever sits at the other end, and that token
    # reads the whole workspace. Named rather than allowed in silence; a
    # loopback host is nobody else's network, so it says nothing there.
    def warn_cleartext!(uri)
      return if uri.scheme == 'https' || loopback?(uri.host)

      ForestAdminDatasourceIntercom.logger.warn(
        "[forest_admin_datasource_intercom] base_url #{redacted_url.inspect} is not https, and every request " \
        'carries the Intercom access token as a bearer header. Anything on the path can read it and use it ' \
        'against the workspace. Use https, or terminate TLS before the network this crosses.'
      )
    end

    def loopback?(host)
      LOOPBACK_HOSTS.include?(host.to_s.downcase) || host.to_s.downcase.end_with?('.localhost')
    end

    def blank?(value)
      value.nil? || value.to_s.strip.empty?
    end
  end
end
