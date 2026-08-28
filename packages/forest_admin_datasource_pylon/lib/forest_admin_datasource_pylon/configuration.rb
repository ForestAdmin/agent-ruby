module ForestAdminDatasourcePylon
  class Configuration
    DEFAULT_BASE_URL = 'https://api.usepylon.com'.freeze

    attr_reader :api_key, :base_url, :open_timeout, :timeout, :retry_policy, :rate_limiter,
                :boot_open_timeout, :boot_timeout, :boot_retry_policy

    # `rate_limiter: nil` takes the throttling out of the stack, leaving the 429
    # retry as the only rate-limit handling. For the deployment metering on its
    # own side, or the one that would rather see the 429.
    #
    # The `boot_` trio governs what the datasource reads while it is being
    # constructed, where the wait is a Rails boot the operator sits through
    # rather than a request that has already returned a page.
    def initialize(api_key:, base_url: nil, open_timeout: 5, timeout: 30, retry_policy: RetryPolicy.new,
                   rate_limiter: RateLimiter.new, boot_open_timeout: 3, boot_timeout: 10,
                   boot_retry_policy: RetryPolicy.boot)
      @api_key      = api_key
      @base_url     = base_url || DEFAULT_BASE_URL
      @open_timeout = open_timeout
      @timeout      = timeout
      @retry_policy = retry_policy
      @rate_limiter = rate_limiter
      @boot_open_timeout = boot_open_timeout
      @boot_timeout      = boot_timeout
      @boot_retry_policy = boot_retry_policy
      validate!
    end

    # Pylon exposes unversioned paths (`/issues`, `/me`) directly under the host.
    def url
      @base_url.chomp('/')
    end

    # Whatever precedes the endpoint in the path, for a base url mounted under a
    # subpath — an egress proxy, or a mock server. Empty against the API itself.
    # `RateLimits` is keyed on the endpoint, so this has to come off a path
    # before the table is asked: left on, every anchored rule misses and the
    # whole datasource meters in one fallback bucket.
    def base_path
      @base_path ||= URI.parse(url).path
    end

    # `api_key` is a bearer token, and nothing prints a Configuration on
    # purpose: what reaches an `inspect` is a Rails error page, or a
    # `logger.debug` of something holding one. The default would put the token
    # in clear there.
    #
    # One of three, not the whole of it: the token also rides in the headers of
    # the client's Faraday connections, which print them in clear, so `Client`
    # and `Datasource` mask their own. Together they cut every path from an
    # object this package hands out to the credential.
    def inspect
      "#<#{self.class.name} base_url=#{@base_url.inspect} api_key=[FILTERED]>"
    end

    private

    def validate!
      missing = []
      missing << 'api_key' if blank?(@api_key)
      return if missing.empty?

      raise ConfigurationError,
            "ForestAdminDatasourcePylon missing required config: #{missing.join(", ")}"
    end

    def blank?(value)
      value.nil? || value.to_s.strip.empty?
    end
  end
end
