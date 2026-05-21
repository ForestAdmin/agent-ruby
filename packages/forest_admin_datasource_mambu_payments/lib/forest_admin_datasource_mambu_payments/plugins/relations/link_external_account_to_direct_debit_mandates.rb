module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # Reciprocal OneToMany on MambuExternalAccount for the native
      # DirectDebitMandate.external_account ManyToOne.
      #
      # Install at the datasource level:
      #   @agent.use(
      #     ForestAdminDatasourceMambuPayments::Plugins::Relations::LinkExternalAccountToDirectDebitMandates,
      #     {}
      #   )
      class LinkExternalAccountToDirectDebitMandates < ForestAdminDatasourceCustomizer::Plugins::Plugin
        EXTERNAL_ACCOUNT     = 'MambuExternalAccount'.freeze
        DIRECT_DEBIT_MANDATE = 'MambuDirectDebitMandate'.freeze

        def run(datasource_customizer, _collection_customizer = nil, _options = {})
          unless datasource_customizer
            raise ArgumentError,
                  'LinkExternalAccountToDirectDebitMandates must be installed at the datasource level ' \
                  'via @agent.use(plugin, {})'
          end

          datasource_customizer.customize_collection(EXTERNAL_ACCOUNT) do |c|
            c.add_one_to_many_relation('direct_debit_mandates', DIRECT_DEBIT_MANDATE,
                                       origin_key: 'external_account_id',
                                       origin_key_target: 'id')
          end
        end
      end
    end
  end
end
