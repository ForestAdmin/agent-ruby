module ForestAdminDatasourceZendesk
  class Configuration
    attr_reader :subdomain, :username, :token

    def initialize(subdomain:, username:, token:)
      @subdomain = subdomain
      @username  = username
      @token     = token
      validate!
    end

    def url
      "https://#{@subdomain}.zendesk.com/api/v2"
    end

    private

    def validate!
      missing = []
      missing << 'subdomain' if blank?(@subdomain)
      missing << 'username'  if blank?(@username)
      missing << 'token'     if blank?(@token)
      return if missing.empty?

      raise ConfigurationError,
            "ForestAdminDatasourceZendesk missing required config: #{missing.join(', ')}"
    end

    def blank?(value)
      value.nil? || value.to_s.strip.empty?
    end
  end
end
