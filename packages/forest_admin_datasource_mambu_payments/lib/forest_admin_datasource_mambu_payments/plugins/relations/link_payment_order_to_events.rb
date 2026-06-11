module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # OneToMany on MambuPaymentOrder for Event.related_object_id.
      # Event.related_object_id is polymorphic (payment_order, transaction,
      # incoming_payment, ...), but UUIDs are globally unique so filtering by
      # id alone yields exactly the events about the given PO.
      #
      # Requires Event.api_filters to expose `related_object_id` — added in
      # the Event collection itself.
      #
      # Install at the datasource level:
      #   @agent.use(
      #     ForestAdminDatasourceMambuPayments::Plugins::Relations::LinkPaymentOrderToEvents,
      #     {}
      #   )
      class LinkPaymentOrderToEvents < ForestAdminDatasourceCustomizer::Plugins::Plugin
        PAYMENT_ORDER = 'MambuPaymentOrder'.freeze
        EVENT         = 'MambuEvent'.freeze

        def run(datasource_customizer, _collection_customizer = nil, _options = {})
          Plugins::Helpers.require_datasource!(datasource_customizer, self.class)

          datasource_customizer.customize_collection(PAYMENT_ORDER) do |c|
            c.add_one_to_many_relation('events', EVENT,
                                       origin_key: 'related_object_id',
                                       origin_key_target: 'id')
          end
        end
      end
    end
  end
end
