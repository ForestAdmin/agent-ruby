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

    # Without an explicit version a request follows the workspace's own default,
    # which an operator can change on Intercom's side -- and the payloads change
    # shape under us. Pinned to what the spike ran against; 2.14 and 2.16 both
    # answered, and the response echoes the version back, so `Client#me`
    # verifies at boot that the pin was honoured.
    DEFAULT_API_VERSION = '2.16'.freeze

    attr_reader :access_token, :region, :base_url, :api_version, :open_timeout, :timeout,
                :retry_policy, :rate_limiter, :boot_open_timeout, :boot_timeout, :boot_retry_policy

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
                   boot_retry_policy: RetryPolicy.boot)
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
      validate!
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

    # `access_token` is a bearer credential, and nothing prints a Configuration
    # on purpose: what reaches an `inspect` is a Rails error page, or a
    # `logger.debug` of something holding one. The default would put the token
    # in clear there. `Client` and `Datasource` mask their own for the same
    # reason -- together they cut every path from an object this package hands
    # out to the credential.
    def inspect
      "#<#{self.class.name} url=#{url.inspect} api_version=#{@api_version.inspect} access_token=[FILTERED]>"
    end

    private

    def validate!
      raise ConfigurationError, 'ForestAdminDatasourceIntercom missing required config: access_token' if
        blank?(@access_token)

      validate_region!
      validate_base_url!
      raise ConfigurationError, 'ForestAdminDatasourceIntercom api_version cannot be empty' if blank?(@api_version)
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
      return if uri.is_a?(URI::HTTP) && !blank?(uri.host)

      raise ConfigurationError,
            "ForestAdminDatasourceIntercom base_url must be an absolute http(s) url, got #{@base_url.inspect}"
    rescue URI::InvalidURIError
      raise ConfigurationError,
            "ForestAdminDatasourceIntercom base_url is not a valid url: #{@base_url.inspect}"
    end

    def blank?(value)
      value.nil? || value.to_s.strip.empty?
    end
  end
end
