require 'ipaddress'
require 'filecache'
require 'json'

module ForestAdminAgent
  module Services
    class IpWhitelist
      RULE_MATCH_IP = 0
      RULE_MATCH_RANGE = 1
      RULE_MATCH_SUBNET = 2
      CACHE_KEY = 'forest.ip_whitelist'.freeze

      attr_reader :forest_api, :cache

      def initialize
        @forest_api = ForestAdminAgent::Http::ForestAdminApiRequester.new
        @cache = FileCache.new(
          'ip_whitelist',
          Facades::Container.config_from_cache[:cache_dir].to_s,
          Facades::Container.config_from_cache[:permission_expiration]
        )
      end

      def self.invalidate_cache
        cache = FileCache.new(
          'ip_whitelist',
          Facades::Container.config_from_cache[:cache_dir].to_s,
          Facades::Container.config_from_cache[:permission_expiration]
        )
        cache.delete(CACHE_KEY) unless cache.get(CACHE_KEY).nil?
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
          raise ForestAdminAgent::Http::Exceptions::InternalServerError, 'Invalid rule type'
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
        ip_whitelist_data = cache.get_or_set(CACHE_KEY) { fetch_ip_whitelist_from_api }

        @use_ip_whitelist = ip_whitelist_data['use_ip_whitelist']
        @rules = ip_whitelist_data['rules']
      end

      def fetch_ip_whitelist_from_api
        response = forest_api.get('/liana/v1/ip-whitelist-rules')

        unless response.status == 200
          ForestAdminAgent::Facades::Container.logger.log('Error', {
                                                            error: "HTTP #{response.status}",
                                                            status: response.status,
                                                            response: response.body
                                                          })
          raise ForestAdminAgent::Http::Exceptions::InternalServerError,
                ForestAdminAgent::Utils::ErrorMessages::UNEXPECTED
        end

        begin
          body = JSON.parse(response.body)
        rescue JSON::ParserError => e
          ForestAdminAgent::Facades::Container.logger.log('Error', {
                                                            error: e.message,
                                                            status: response.status,
                                                            response: response.body
                                                          })
          raise ForestAdminAgent::Http::Exceptions::InternalServerError,
                ForestAdminAgent::Utils::ErrorMessages::UNEXPECTED
        end

        body['data']['attributes']
      rescue StandardError => e
        ForestAdminAgent::Facades::Container.logger.log('Debug', {
                                                          error: e.message,
                                                          status: response&.status,
                                                          response: response&.body
                                                        })
        raise ForestAdminAgent::Http::Exceptions::InternalServerError,
              ForestAdminAgent::Utils::ErrorMessages::UNEXPECTED
      end
    end
  end
end
