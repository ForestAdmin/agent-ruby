module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # OneToMany on MambuPaymentOrder for Return.related_payment_id.
      # Return.related_payment_id is polymorphic (payment_order or
      # incoming_payment), but UUIDs are globally unique so filtering by id
      # alone yields exactly the returns belonging to the given PO. The same
      # column can later be used to expose `returns` on MambuIncomingPayment
      # without conflict.
      #
      # Install at the datasource level:
      #   @agent.use(
      #     ForestAdminDatasourceMambuPayments::Plugins::Relations::LinkPaymentOrderToReturns,
      #     {}
      #   )
      class LinkPaymentOrderToReturns < ForestAdminDatasourceCustomizer::Plugins::Plugin
        PAYMENT_ORDER = 'MambuPaymentOrder'.freeze
        RETURN_COLL   = 'MambuReturn'.freeze

        def run(datasource_customizer, _collection_customizer = nil, _options = {})
          unless datasource_customizer
            raise ArgumentError,
                  'LinkPaymentOrderToReturns must be installed at the datasource level ' \
                  'via @agent.use(plugin, {})'
          end

          datasource_customizer.customize_collection(PAYMENT_ORDER) do |c|
            c.add_one_to_many_relation('returns', RETURN_COLL,
                                       origin_key: 'related_payment_id',
                                       origin_key_target: 'id')
          end
        end
      end
    end
  end
end
