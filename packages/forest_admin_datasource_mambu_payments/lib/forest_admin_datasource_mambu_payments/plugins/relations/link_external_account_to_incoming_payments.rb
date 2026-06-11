module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # Reciprocal OneToMany on MambuExternalAccount for the native
      # IncomingPayment.external_account ManyToOne.
      #
      # Install at the datasource level:
      #   @agent.use(
      #     ForestAdminDatasourceMambuPayments::Plugins::Relations::LinkExternalAccountToIncomingPayments,
      #     {}
      #   )
      class LinkExternalAccountToIncomingPayments < ForestAdminDatasourceCustomizer::Plugins::Plugin
        EXTERNAL_ACCOUNT = 'MambuExternalAccount'.freeze
        INCOMING_PAYMENT = 'MambuIncomingPayment'.freeze

        def run(datasource_customizer, _collection_customizer = nil, _options = {})
          Plugins::Helpers.require_datasource!(datasource_customizer, self.class)

          datasource_customizer.customize_collection(EXTERNAL_ACCOUNT) do |c|
            c.add_one_to_many_relation('incoming_payments', INCOMING_PAYMENT,
                                       origin_key: 'external_account_id',
                                       origin_key_target: 'id')
          end
        end
      end
    end
  end
end
