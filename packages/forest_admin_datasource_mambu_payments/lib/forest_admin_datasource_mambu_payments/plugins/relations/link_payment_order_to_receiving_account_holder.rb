module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # Exposes a navigable PaymentOrder <-> AccountHolder link.
      # The chain is transitive: PO.receiving_account_id -> ExternalAccount.account_holder_id.
      # Named `receiving_account_holder` rather than `account_holder` to make it
      # explicit that this is the counterparty (receiving) account's holder,
      # not the holder of our own (internal) side of the order.
      # See TwoStepHolderFilter for the OneToMany filter rewrite.
      #
      # Install at the datasource level:
      #   @agent.use(
      #     ForestAdminDatasourceMambuPayments::Plugins::Relations::LinkPaymentOrderToReceivingAccountHolder,
      #     {}
      #   )
      class LinkPaymentOrderToReceivingAccountHolder < ForestAdminDatasourceCustomizer::Plugins::Plugin
        PAYMENT_ORDER    = 'MambuPaymentOrder'.freeze
        EXTERNAL_ACCOUNT = 'MambuExternalAccount'.freeze
        ACCOUNT_HOLDER   = 'MambuAccountHolder'.freeze
        FK_NAME          = 'account_holder_id'.freeze
        LOCAL_FK         = 'receiving_account_id'.freeze
        IMPORT_PATH      = 'external_account:account_holder_id'.freeze
        MANY_TO_ONE_NAME = 'receiving_account_holder'.freeze
        ONE_TO_MANY_NAME = 'payment_orders'.freeze

        def run(datasource_customizer, _collection_customizer = nil, _options = {})
          unless datasource_customizer
            raise ArgumentError,
                  'LinkPaymentOrderToReceivingAccountHolder must be installed at the datasource level ' \
                  'via @agent.use(plugin, {})'
          end

          datasource_customizer.customize_collection(PAYMENT_ORDER) do |c|
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
            c.add_one_to_many_relation(ONE_TO_MANY_NAME, PAYMENT_ORDER,
                                       origin_key: FK_NAME,
                                       origin_key_target: 'id')
          end
        end
      end
    end
  end
end
