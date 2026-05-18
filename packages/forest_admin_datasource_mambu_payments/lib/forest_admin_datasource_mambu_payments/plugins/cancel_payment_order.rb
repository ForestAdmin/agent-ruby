module ForestAdminDatasourceMambuPayments
  module Plugins
    # Cancels a payment order. The optional `reason` is only used by Numeral
    # for SEPA direct debit cancelations before settlement; for other payment
    # types it is accepted and ignored.
    class CancelPaymentOrder < ForestAdminDatasourceCustomizer::Plugins::Plugin
      BaseAction  = ForestAdminDatasourceCustomizer::Decorators::Action::BaseAction
      ActionScope = ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope
      FieldType   = ForestAdminDatasourceCustomizer::Decorators::Action::Types::FieldType

      NAMES = { single: 'Cancel Mambu payment order',
                bulk: 'Cancel selected Mambu payment orders' }.freeze

      def run(_datasource_customizer, collection_customizer = nil, options = {})
        datasource = options[:datasource]
        record_id_field = options[:record_id_field]
        raise ArgumentError, 'CancelPaymentOrder plugin requires :datasource' unless datasource
        raise ArgumentError, 'CancelPaymentOrder plugin requires :record_id_field' unless record_id_field
        raise ArgumentError, 'CancelPaymentOrder plugin requires a collection' unless collection_customizer

        Helpers.normalize_scopes(options[:scopes]).each do |scope_key|
          collection_customizer.add_action(NAMES[scope_key], build_action(datasource, scope_key, record_id_field))
        end
      end

      private

      def build_action(datasource, scope_key, record_id_field)
        BaseAction.new(scope: Helpers::SCOPES[scope_key], form: form, &executor(datasource, record_id_field))
      end

      def form
        [{ type: FieldType::STRING, label: 'Reason',
           description: 'Optional reason code (SEPA direct debit only).' }]
      end

      def executor(datasource, record_id_field)
        lambda do |context, result_builder|
          ids = Helpers.resolve_ids(context, record_id_field)
          next result_builder.error(message: "No Mambu payment order id found in '#{record_id_field}'.") if ids.empty?

          payload = {}
          reason = context.form_values['Reason']
          payload['reason'] = reason if Helpers.present?(reason)

          succeeded, failed = Helpers.each_with_rescue(ids, 'cancel_payment_order') do |id|
            datasource.client.cancel_payment_order(id, payload)
          end
          finalize(result_builder, succeeded, failed)
        end
      end

      def finalize(result_builder, succeeded, failed)
        if succeeded.empty?
          return result_builder.error(message: Messages.all_failed(failed, noun: 'payment order',
                                                                           verb: 'cancel'))
        end

        result_builder.success(message: Messages.success(succeeded, failed, noun: 'payment order',
                                                                            verb_past: 'canceled'))
      end
    end
  end
end
