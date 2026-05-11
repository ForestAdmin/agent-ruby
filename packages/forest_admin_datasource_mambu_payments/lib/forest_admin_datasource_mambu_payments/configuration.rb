module ForestAdminDatasourceMambuPayments
  class Configuration
    DEFAULT_BASE_URL = 'https://api.numeral.io'.freeze
    SANDBOX_BASE_URL = 'https://api.sandbox.numeral.io'.freeze
    API_VERSION      = 'v1'.freeze

    attr_reader :api_key, :base_url, :open_timeout, :timeout

    def initialize(api_key:, base_url: nil, sandbox: false, open_timeout: 5, timeout: 30)
      @api_key      = api_key
      @base_url     = base_url || (sandbox ? SANDBOX_BASE_URL : DEFAULT_BASE_URL)
      @open_timeout = open_timeout
      @timeout      = timeout
      validate!
    end

    def url
      "#{@base_url.chomp("/")}/#{API_VERSION}"
    end

    private

    def validate!
      missing = []
      missing << 'api_key' if blank?(@api_key)
      return if missing.empty?

      raise ConfigurationError,
            "ForestAdminDatasourceMambuPayments missing required config: #{missing.join(", ")}"
    end

    def blank?(value)
      value.nil? || value.to_s.strip.empty?
    end
  end
end
