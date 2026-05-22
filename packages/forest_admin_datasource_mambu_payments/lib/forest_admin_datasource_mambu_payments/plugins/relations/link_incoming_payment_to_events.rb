module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # OneToMany on MambuIncomingPayment for Event.related_object_id.
      # Event.related_object_id is polymorphic (incoming_payment, payment_order,
      # transaction, ...), but UUIDs are globally unique so filtering by id
      # alone yields exactly the events about the given IP.
      #
      # Requires Event.api_filters to expose `related_object_id` — declared in
      # the Event collection itself.
      #
      # Install at the datasource level:
      #   @agent.use(
      #     ForestAdminDatasourceMambuPayments::Plugins::Relations::LinkIncomingPaymentToEvents,
      #     {}
      #   )
      class LinkIncomingPaymentToEvents < ForestAdminDatasourceCustomizer::Plugins::Plugin
        INCOMING_PAYMENT = 'MambuIncomingPayment'.freeze
        EVENT            = 'MambuEvent'.freeze

        def run(datasource_customizer, _collection_customizer = nil, _options = {})
          unless datasource_customizer
            raise ArgumentError,
                  'LinkIncomingPaymentToEvents must be installed at the datasource level ' \
                  'via @agent.use(plugin, {})'
          end

          datasource_customizer.customize_collection(INCOMING_PAYMENT) do |c|
            c.add_one_to_many_relation('events', EVENT,
                                       origin_key: 'related_object_id',
                                       origin_key_target: 'id')
          end
        end
      end
    end
  end
end
