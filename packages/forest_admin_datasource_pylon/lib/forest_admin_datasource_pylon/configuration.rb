module ForestAdminDatasourcePylon
  class Configuration
    DEFAULT_BASE_URL = 'https://api.usepylon.com'.freeze

    attr_reader :api_key, :base_url, :open_timeout, :timeout, :max_retries, :retry_interval

    def initialize(api_key:, base_url: nil, open_timeout: 5, timeout: 30, max_retries: 3, retry_interval: 0.5)
      @api_key        = api_key
      @base_url       = base_url || DEFAULT_BASE_URL
      @open_timeout   = open_timeout
      @timeout        = timeout
      @max_retries    = max_retries
      @retry_interval = retry_interval
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
