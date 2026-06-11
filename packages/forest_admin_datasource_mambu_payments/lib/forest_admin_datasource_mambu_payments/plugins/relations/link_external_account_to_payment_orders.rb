module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # Reciprocal OneToMany on MambuExternalAccount for the native
      # PaymentOrder.external_account ManyToOne (FK: receiving_account_id).
      #
      # Install at the datasource level:
      #   @agent.use(
      #     ForestAdminDatasourceMambuPayments::Plugins::Relations::LinkExternalAccountToPaymentOrders,
      #     {}
      #   )
      class LinkExternalAccountToPaymentOrders < ForestAdminDatasourceCustomizer::Plugins::Plugin
        EXTERNAL_ACCOUNT = 'MambuExternalAccount'.freeze
        PAYMENT_ORDER    = 'MambuPaymentOrder'.freeze

        def run(datasource_customizer, _collection_customizer = nil, _options = {})
          Plugins::Helpers.require_datasource!(datasource_customizer, self.class)

          datasource_customizer.customize_collection(EXTERNAL_ACCOUNT) do |c|
            c.add_one_to_many_relation('payment_orders', PAYMENT_ORDER,
                                       origin_key: 'receiving_account_id',
                                       origin_key_target: 'id')
          end
        end
      end
    end
  end
end
