module ForestAdminDatasourceIntercom
  class Configuration
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

    # How long the workspace's reference lists -- teammates, teams, ticket types,
    # ticket states -- are reused before being read again. They are what every
    # relation of this datasource resolves through, so without a window a single
    # ticket list spends four sequential round trips on lists that change a few
    # times a year, and spends them again on the next page.
    #
    # A minute is what keeps a teammate added mid-session from being invisible
    # for longer than an operator would notice, while collapsing the four reads
    # of a browsing session into four reads a minute. `0` takes the store out of
    # the stack. Records are never cached, whatever this says -- see `Cache`.
    DEFAULT_REFERENCE_CACHE_TTL = 60

    # Keep-alive, and the reason it is worth a dependency: a ticket list is
    # seven requests to the same host, and the default adapter opens a TCP
    # connection and negotiates TLS for every one of them. The handshakes cost
    # more than several of the requests they carry.
    #
    # Resolved rather than hardcoded, so a deployment that cannot load the
    # persistent adapter -- or would rather not pool -- falls back to Faraday's
    # default instead of failing to boot. `adapter: :net_http` opts out
    # explicitly; `adapter: [:net_http_persistent, { pool_size: 25 }]` sizes the
    # pool for a wider thread pool than the default.
    DEFAULT_ADAPTER = [:net_http_persistent, { pool_size: 10 }].freeze

    attr_reader :access_token, :region, :base_url, :api_version, :open_timeout, :timeout,
                :retry_policy, :rate_limiter, :boot_open_timeout, :boot_timeout, :boot_retry_policy,
                :reference_cache_ttl, :adapter, :reference_cache

    # `rate_limiter: nil` takes the pacing out of the stack, leaving the 429
    # retry as the only rate-limit handling. For a deployment that meters on its
    # own side, or one that would rather see the 429.
    #
    # The `boot_` trio governs what the datasource reads while it is being
    # constructed -- the custom-attribute introspection above all -- where the
    # wait is a Rails boot the operator sits through rather than a request that
    # has already returned a page.
    def initialize(access_token:, region: nil, base_url: nil, api_version: DEFAULT_API_VERSION,
                   open_timeout: 5, timeout: 30, retry_policy: RetryPolicy.new,
                   rate_limiter: RateLimiter.new, boot_open_timeout: 3, boot_timeout: 10,
                   boot_retry_policy: RetryPolicy.boot,
                   reference_cache_ttl: DEFAULT_REFERENCE_CACHE_TTL, adapter: nil)
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
      @reference_cache_ttl = reference_cache_ttl.to_f
      @adapter = adapter
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

    # Whatever precedes the endpoint in the path, for a base url mounted under a
    # subpath. Empty against the API itself.
    def base_path
      @base_path ||= URI.parse(url).path
    end

    # The url with any credentials in it masked. `URI` accepts them --
    # `https://user:pass@proxy/...` -- and a credentialed egress proxy is one of
    # the two reasons to set a `base_url` at all, so printing the url verbatim
    # would put a second secret exactly where this class keeps the first one
    # from going. Read by `Client#inspect` too, which prints the same url.
    def redacted_url
      @redacted_url ||= url.sub(%r{\A([a-zA-Z][\w+.-]*://)[^/@]*@}, '\1[FILTERED]@')
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

      return unless @reference_cache_ttl.negative?

      raise ConfigurationError,
            'ForestAdminDatasourceIntercom reference_cache_ttl must be zero or more seconds, got ' \
            "#{@reference_cache_ttl}"
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
      return warn_cleartext!(uri) if uri.is_a?(URI::HTTP) && !blank?(uri.host)

      raise ConfigurationError,
            "ForestAdminDatasourceIntercom base_url must be an absolute http(s) url, got #{@base_url.inspect}"
    rescue URI::InvalidURIError
      raise ConfigurationError,
            "ForestAdminDatasourceIntercom base_url is not a valid url: #{@base_url.inspect}"
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
