module ForestAdminDatasourceMambuPayments
  module Plugins
    module SmartActions
      # Approves a payment order in status `pending_approval`. The Numeral API
      # rejects approval for orders in any other status, so per-id rescue keeps
      # one bad id from aborting a bulk approval.
      class ApprovePaymentOrder < ForestAdminDatasourceCustomizer::Plugins::Plugin
        BaseAction  = ForestAdminDatasourceCustomizer::Decorators::Action::BaseAction
        ActionScope = ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope

        NAMES = { single: 'Approve Mambu payment order',
                  bulk: 'Approve selected Mambu payment orders' }.freeze

        def run(_datasource_customizer, collection_customizer = nil, options = {})
          datasource = options[:datasource]
          record_id_field = options[:record_id_field]
          raise ArgumentError, 'ApprovePaymentOrder plugin requires :datasource' unless datasource
          raise ArgumentError, 'ApprovePaymentOrder plugin requires :record_id_field' unless record_id_field
          raise ArgumentError, 'ApprovePaymentOrder plugin requires a collection' unless collection_customizer

          Helpers.normalize_scopes(options[:scopes]).each do |scope_key|
            collection_customizer.add_action(NAMES[scope_key], build_action(datasource, scope_key, record_id_field))
          end
        end

        private

        def build_action(datasource, scope_key, record_id_field)
          BaseAction.new(scope: Helpers::SCOPES[scope_key], &executor(datasource, record_id_field))
        end

        def executor(datasource, record_id_field)
          lambda do |context, result_builder|
            ids = Helpers.resolve_ids(context, record_id_field)
            next result_builder.error(message: "No Mambu payment order id found in '#{record_id_field}'.") if ids.empty?

            succeeded, failed = Helpers.each_with_rescue(ids, 'approve_payment_order') do |id|
              datasource.client.approve_payment_order(id)
            end
            finalize(result_builder, succeeded, failed)
          end
        end

        def finalize(result_builder, succeeded, failed)
          if succeeded.empty?
            return result_builder.error(message: Messages.all_failed(failed, noun: 'payment order',
                                                                             verb: 'approve'))
          end

          result_builder.success(message: Messages.success(succeeded, failed, noun: 'payment order',
                                                                              verb_past: 'approved'))
        end
      end
    end
  end
end
