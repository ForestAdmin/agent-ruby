require 'ld-eventsource'

module ForestAdminAgent
  module Services
    class SSECacheInvalidation
      include ForestAdminAgent::Http::Exceptions
      include ForestAdminDatasourceToolkit::Exceptions

      MESSAGE_CACHE_KEYS = {
        'refresh-users': %w[forest.users],
        'refresh-roles': %w[forest.collections],
        'refresh-renderings': %w[forest.collections]
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
              invalidate_renderings(event.data) if event.type == :'refresh-renderings'

              ForestAdminAgent::Facades::Container.logger.log(
                'Info',
                "SSECacheInvalidation: unhandled message from server: #{event.type}"
              )
            end
          end
        rescue StandardError => e
          ForestAdminAgent::Facades::Container.logger.log(
            'Debug',
            'SSE connection to forestadmin server'
          )

          ForestAdminAgent::Facades::Container.logger.log(
            'Warning',
            'SSE connection to forestadmin server closed unexpectedly, retrying.'
          )

          raise ServiceUnavailableError.new(
            'Failed to reach SSE data from ForestAdmin server',
            details: { error: e.message },
            cause: e
          )
        end
      end

      # An event that does not name its renderings could concern any of them, so all are dropped.
      def self.invalidate_renderings(data)
        rendering_ids = begin
          JSON.parse(data.to_s)['renderingIds']
        rescue JSON::ParserError, TypeError
          nil
        end

        if rendering_ids.is_a?(Array) && rendering_ids.any?
          rendering_ids.each { |rendering_id| Permissions.invalidate_rendering_cache(rendering_id) }
        else
          Permissions.invalidate_rendering_cache
        end
      end
      private_class_method :invalidate_renderings
    end
  end
end
