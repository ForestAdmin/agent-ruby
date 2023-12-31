module ForestAdminAgent
  module Facades
    class Whitelist
      def self.check_ip(request_ip)
        ip_whitelist = ForestAdminAgent::Services::IpWhitelist.new
        return unless ip_whitelist.enabled?
        return if ip_whitelist.ip_matches_any_rule?(request_ip)

        raise Net::HTTPExceptions, "IP address rejected (#{request_ip})"
      end
    end
  end
end
