require 'ipaddress'
require 'net/http'

module ForestAdminAgent
  module Services
    class IpWhitelist
      RULE_MATCH_IP = 0
      RULE_MATCH_RANGE = 1
      RULE_MATCH_SUBNET = 2

      def initialize
        fetch_rules
      end

      def use_ip_whitelist
        @use_ip_whitelist ||= false
      end

      def rules
        @rules ||= []
      end

      def enabled?
        use_ip_whitelist && !rules.empty?
      end

      def ip_matches_any_rule?(ip)
        rules.any? { |rule| ip_matches_rule?(ip, rule) }
      end

      def ip_matches_rule?(ip, rule)
        case rule['type']
        when RULE_MATCH_IP
          ip_match_ip?(ip, rule['ip'])
        when RULE_MATCH_RANGE
          ip_match_range?(ip, rule['ipMinimum'], rule['ipMaximum'])
        when RULE_MATCH_SUBNET
          ip_match_subnet?(ip, rule['range'])
        else
          raise 'Invalid rule type'
        end
      end

      def ip_match_ip?(ip1, ip2)
        return both_loopback?(ip1, ip2) unless same_ip_version?(ip1, ip2)

        if ip1 == ip2
          true
        else
          both_loopback?(ip1, ip2)
        end
      end

      def same_ip_version?(ip1, ip2)
        ip_version(ip1) == ip_version(ip2)
      end

      def ip_version(ip)
        (IPAddress ip).is_a?(IPAddress::IPv4) ? :ip_v4 : :ip_v6
      end

      def both_loopback?(ip1, ip2)
        IPAddress(ip1).loopback? && IPAddress(ip2).loopback?
      end

      def ip_match_range?(ip, min, max)
        return false unless same_ip_version?(ip, min)

        ip_range_minimum = (IPAddress min)
        ip_range_maximum = (IPAddress max)
        ip_value = (IPAddress ip)

        ip_value >= ip_range_minimum && ip_value <= ip_range_maximum
      end

      def ip_match_subnet?(ip, subnet)
        return false unless same_ip_version?(ip, subnet)

        IPAddress(subnet).include?(IPAddress(ip))
      end

      private

      def fetch_rules
        response = Net::HTTP.get_response(
          URI("#{Facades::Container.cache(:forest_server_url)}/liana/v1/ip-whitelist-rules"),
          { 'Content-Type' => 'application/json', 'forest-secret-key' => Facades::Container.cache(:env_secret) }
        )

        raise Error, ForestAdminAgent::Utils::ErrorMessages::UNEXPECTED unless response.is_a?(Net::HTTPSuccess)

        body = JSON.parse(response.body)
        ip_whitelist_data = body['data']['attributes']

        @use_ip_whitelist = ip_whitelist_data['use_ip_whitelist']
        @rules = ip_whitelist_data['rules']
      end
    end
  end
end
