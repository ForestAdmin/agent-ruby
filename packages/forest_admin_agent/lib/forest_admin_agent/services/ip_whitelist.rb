require 'ipaddress'

module ForestAdminAgent
  module Services
    class IpWhitelist
      RULE_MATCH_IP = 0
      RULE_MATCH_RANGE = 1
      RULE_MATCH_SUBNET = 2

      attr_reader :forest_api

      def initialize
        @forest_api = ForestAdminAgent::Http::ForestAdminApiRequester.new
      end

      def use_ip_whitelist
        fetch_rules if @use_ip_whitelist.nil?
        @use_ip_whitelist ||= false
      end

      def rules
        fetch_rules if @rules.nil?
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

        ip_value.between?(ip_range_minimum, ip_range_maximum)
      end

      def ip_match_subnet?(ip, subnet)
        return false unless same_ip_version?(ip, subnet)

        IPAddress(subnet).include?(IPAddress(ip))
      end

      private

      def fetch_rules
        response = forest_api.get('/liana/v1/ip-whitelist-rules')

        body = JSON.parse(response.body)
        ip_whitelist_data = body['data']['attributes']

        @use_ip_whitelist = ip_whitelist_data['use_ip_whitelist']
        @rules = ip_whitelist_data['rules']
      rescue StandardError => e
        ForestAdminAgent::Facades::Container.logger.log('Debug', {
                                                          error: e.message,
                                                          status: response&.status,
                                                          response: response&.body
                                                        })
        raise ForestAdminAgent::Error, ForestAdminAgent::Utils::ErrorMessages::UNEXPECTED
      end
    end
  end
end
