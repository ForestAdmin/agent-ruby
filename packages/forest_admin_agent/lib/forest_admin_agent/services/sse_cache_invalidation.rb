require 'ld-eventsource'

module ForestAdminAgent
  module Services
    class SSECacheInvalidation
      include ForestAdminDatasourceToolkit::Exceptions

      MESSAGE_CACHE_KEYS = {
        'refresh-users': %w[forest.users],
        'refresh-roles': %w[forest.collections],
        'refresh-renderings': %w[forest.collections forest.stats forest.scopes]
        # TODO: add one for ip whitelist when server implement it
      }.freeze

      def self.run
        uri = "#{Facades::Container.config_from_cache[:forest_server_url]}/liana/v4/subscribe-to-events"
        headers = {
          'forest-secret-key' => Facades::Container.config_from_cache[:env_secret],
          'Accept' => 'text/event-stream'
        }

        begin
          SSE::Client.new(uri, headers: headers) do |client|
            client.on_event do |event|
              next if event.type == :heartbeat

              MESSAGE_CACHE_KEYS[event.type]&.each do |cache_key|
                Permissions.invalidate_cache(cache_key)
                ForestAdminAgent::Facades::Container.logger.log(
                  'Info',
                  "invalidate cache #{MESSAGE_CACHE_KEYS[event.type]} for event #{event.type}"
                )
              end

              ForestAdminAgent::Facades::Container.logger.log(
                'Info',
                "SSECacheInvalidation: unhandled message from server: #{event.type}"
              )
            end
          end
        rescue StandardError
          ForestAdminAgent::Facades::Container.logger.log(
            'Debug',
            'SSE connection to forestadmin server'
          )

          ForestAdminAgent::Facades::Container.logger.log(
            'Warning',
            'SSE connection to forestadmin server closed unexpectedly, retrying.'
          )

          raise ForestException, 'Failed to reach SSE data from ForestAdmin server.'
        end
      end
    end
  end
end
