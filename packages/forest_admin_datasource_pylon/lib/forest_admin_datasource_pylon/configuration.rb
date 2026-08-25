module ForestAdminDatasourcePylon
  class Configuration
    DEFAULT_BASE_URL = 'https://api.usepylon.com'.freeze

    attr_reader :api_key, :base_url, :open_timeout, :timeout, :retry_policy, :rate_limiter

    # `rate_limiter: nil` takes the throttling out of the stack, leaving the 429
    # retry as the only rate-limit handling. For the deployment metering on its
    # own side, or the one that would rather see the 429.
    def initialize(api_key:, base_url: nil, open_timeout: 5, timeout: 30, retry_policy: RetryPolicy.new,
                   rate_limiter: RateLimiter.new)
      @api_key      = api_key
      @base_url     = base_url || DEFAULT_BASE_URL
      @open_timeout = open_timeout
      @timeout      = timeout
      @retry_policy = retry_policy
      @rate_limiter = rate_limiter
      validate!
    end

    # Pylon exposes unversioned paths (`/issues`, `/me`) directly under the host.
    def url
      @base_url.chomp('/')
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
