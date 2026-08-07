module ForestAdminDatasourcePylon
  class Configuration
    DEFAULT_BASE_URL = 'https://api.usepylon.com'.freeze

    # Pylon quotas are per-minute, so a 429 routinely carries a Retry-After of up
    # to 60s. faraday-retry gives up outright when Retry-After exceeds this cap
    # (middleware.rb: `return if retry_after > max_interval`), so it has to cover
    # a full rate-limit window or the 429 retry never fires when it matters.
    DEFAULT_MAX_RETRY_INTERVAL = 65

    attr_reader :api_key, :base_url, :open_timeout, :timeout, :max_retries, :retry_interval,
                :max_retry_interval

    def initialize(api_key:, base_url: nil, open_timeout: 5, timeout: 30, max_retries: 3,
                   retry_interval: 0.5, max_retry_interval: DEFAULT_MAX_RETRY_INTERVAL)
      @api_key            = api_key
      @base_url           = base_url || DEFAULT_BASE_URL
      @open_timeout       = open_timeout
      @timeout            = timeout
      @max_retries        = max_retries
      @retry_interval     = retry_interval
      @max_retry_interval = max_retry_interval
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
