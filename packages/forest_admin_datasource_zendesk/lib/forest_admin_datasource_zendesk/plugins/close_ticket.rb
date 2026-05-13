module ForestAdminDatasourceZendesk
  module Plugins
    # Registers "Mark as solved" / "Mark as closed" smart actions on an
    # arbitrary host collection. The host record(s) must carry a column
    # (`ticket_id_field`) holding the Zendesk ticket id to close.
    class CloseTicket < ForestAdminDatasourceCustomizer::Plugins::Plugin
      def run(_datasource_customizer, collection_customizer = nil, options = {})
        datasource = options[:datasource]
        ticket_id_field = options[:ticket_id_field]
        raise ArgumentError, 'CloseTicket plugin requires :datasource' unless datasource
        raise ArgumentError, 'CloseTicket plugin requires :ticket_id_field' unless ticket_id_field
        raise ArgumentError, 'CloseTicket plugin requires a collection' unless collection_customizer

        Actions::CloseTicket.register_on(
          collection_customizer, datasource,
          ticket_id_field: ticket_id_field,
          statuses: options[:statuses]
        )
      end
    end
  end
end
