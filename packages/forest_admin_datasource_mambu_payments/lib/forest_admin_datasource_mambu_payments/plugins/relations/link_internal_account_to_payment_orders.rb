module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # Exposes a navigable InternalAccount <-> PaymentOrder link.
      # The chain is transitive: PO.connected_account_id is matched against
      # the InternalAccount.connected_account_ids array.
      # See TwoStepConnectedAccountFilter for the OneToMany filter rewrite.
      #
      # Install at the datasource level:
      #   @agent.use(
      #     ForestAdminDatasourceMambuPayments::Plugins::Relations::LinkInternalAccountToPaymentOrders,
      #     {}
      #   )
      class LinkInternalAccountToPaymentOrders < ForestAdminDatasourceCustomizer::Plugins::Plugin
        ComputedDefinition = ForestAdminDatasourceCustomizer::Decorators::Computed::ComputedDefinition

        PAYMENT_ORDER    = 'MambuPaymentOrder'.freeze
        INTERNAL_ACCOUNT = 'MambuInternalAccount'.freeze
        FK_NAME          = 'internal_account_id'.freeze
        LOCAL_FK         = 'connected_account_id'.freeze
        ONE_TO_MANY_NAME = 'payment_orders'.freeze

        def run(datasource_customizer, _collection_customizer = nil, _options = {})
          Plugins::Helpers.require_datasource!(datasource_customizer, self.class)

          datasource_customizer.customize_collection(PAYMENT_ORDER) do |c|
            # Virtual column: PaymentOrder has no native internal_account_id.
            # The value is nil per record (reverse lookup would require scanning
            # all internal accounts) — only EQUAL/IN are rewritten via the
            # TwoStepConnectedAccountFilter below.
            c.add_field(FK_NAME, ComputedDefinition.new(
                                   column_type: 'String',
                                   dependencies: ['id'],
                                   values: proc { |records, _ctx| records.map { nil } }
                                 ))
            TwoStepConnectedAccountFilter.install(c, target_field: LOCAL_FK)
          end

          datasource_customizer.customize_collection(INTERNAL_ACCOUNT) do |c|
            c.add_one_to_many_relation(ONE_TO_MANY_NAME, PAYMENT_ORDER,
                                       origin_key: FK_NAME,
                                       origin_key_target: 'id')
          end
        end
      end
    end
  end
end
