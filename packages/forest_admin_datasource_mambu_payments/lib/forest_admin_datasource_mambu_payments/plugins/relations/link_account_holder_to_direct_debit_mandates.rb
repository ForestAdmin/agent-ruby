module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # Exposes a navigable AccountHolder <-> DirectDebitMandate link.
      # The chain is transitive: DDM -> external_account -> account_holder.
      # See TwoStepHolderFilter for the OneToMany filter rewrite.
      #
      # Install at the datasource level:
      #   @agent.use(
      #     ForestAdminDatasourceMambuPayments::Plugins::Relations::LinkAccountHolderToDirectDebitMandates,
      #     {}
      #   )
      class LinkAccountHolderToDirectDebitMandates < ForestAdminDatasourceCustomizer::Plugins::Plugin
        DIRECT_DEBIT_MANDATE    = 'MambuDirectDebitMandate'.freeze
        EXTERNAL_ACCOUNT        = 'MambuExternalAccount'.freeze
        ACCOUNT_HOLDER          = 'MambuAccountHolder'.freeze
        FK_NAME                 = 'account_holder_id'.freeze
        LOCAL_FK                = 'external_account_id'.freeze
        IMPORT_PATH             = 'external_account:account_holder_id'.freeze
        MANY_TO_ONE_NAME        = 'account_holder'.freeze
        ONE_TO_MANY_NAME        = 'direct_debit_mandates'.freeze

        def run(datasource_customizer, _collection_customizer = nil, _options = {})
          unless datasource_customizer
            raise ArgumentError,
                  'LinkAccountHolderToDirectDebitMandates must be installed at the datasource level ' \
                  'via @agent.use(plugin, {})'
          end

          datasource_customizer.customize_collection(DIRECT_DEBIT_MANDATE) do |c|
            c.import_field(FK_NAME, path: IMPORT_PATH, readonly: true)
            c.add_many_to_one_relation(MANY_TO_ONE_NAME, ACCOUNT_HOLDER,
                                       foreign_key: FK_NAME,
                                       foreign_key_target: 'id')
            TwoStepHolderFilter.install(c,
                                        fk_name: FK_NAME,
                                        local_fk: LOCAL_FK,
                                        intermediate_collection: EXTERNAL_ACCOUNT)
          end

          datasource_customizer.customize_collection(ACCOUNT_HOLDER) do |c|
            c.add_one_to_many_relation(ONE_TO_MANY_NAME, DIRECT_DEBIT_MANDATE,
                                       origin_key: FK_NAME,
                                       origin_key_target: 'id')
          end
        end
      end
    end
  end
end
