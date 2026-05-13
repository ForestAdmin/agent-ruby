module ForestAdminDatasourceZendesk
  module Plugins
    # Registers the "Create ticket and notify" smart action on an arbitrary
    # host collection. The Zendesk datasource instance must be passed in via
    # options so the action can reach the client; everything else mirrors
    # Actions::CreateTicketWithNotification.register_on.
    class CreateTicketWithNotification < ForestAdminDatasourceCustomizer::Plugins::Plugin
      def run(_datasource_customizer, collection_customizer = nil, options = {})
        datasource = options[:datasource]
        raise ArgumentError, 'CreateTicketWithNotification plugin requires :datasource' unless datasource
        raise ArgumentError, 'CreateTicketWithNotification plugin requires a collection' unless collection_customizer

        Actions::CreateTicketWithNotification.register_on(
          collection_customizer, datasource, **options.except(:datasource)
        )
      end
    end
  end
end
