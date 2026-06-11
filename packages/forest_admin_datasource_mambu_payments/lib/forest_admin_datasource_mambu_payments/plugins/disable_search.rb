module ForestAdminDatasourceMambuPayments
  module Plugins
    # Numeral's list endpoints have no free-text search. Forest emulates search
    # by OR-ing a condition over every searchable column, which the
    # ConditionTreeTranslator deliberately rejects (it cannot push an OR to
    # Numeral) — so an operator typing in the search bar would get an error.
    #
    # This plugin turns the search bar off on every Mambu collection, which is
    # the honest behaviour: the API can filter (per `api_filters`) but not
    # search. Install it once at the datasource level:
    #
    #   @agent.use(ForestAdminDatasourceMambuPayments::Plugins::DisableSearch, {})
    class DisableSearch < ForestAdminDatasourceCustomizer::Plugins::Plugin
      COLLECTIONS = %w[
        MambuConnectedAccount MambuPaymentOrder MambuTransaction MambuBalance
        MambuAccountHolder MambuExternalAccount MambuInternalAccount
        MambuIncomingPayment MambuDirectDebitMandate MambuExpectedPayment
        MambuEvent MambuFile MambuReturn MambuClaim MambuReconciliation
        MambuPaymentCapture MambuPayeeVerificationRequest
      ].freeze

      def run(datasource_customizer, _collection_customizer = nil, _options = {})
        Helpers.require_datasource!(datasource_customizer, self.class)

        COLLECTIONS.each do |name|
          datasource_customizer.customize_collection(name, &:disable_search)
        end
      end
    end
  end
end
