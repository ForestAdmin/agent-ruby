module ForestAdminDatasourceMambuPayments
  module Plugins
    # Triggers Numeral's asynchronous external-account verification (a.k.a.
    # Verification of Payee / VOP). The API returns immediately with status
    # `pending_verification`; the actual result lands ~30s later via webhook.
    class TriggerPayeeVerification < ForestAdminDatasourceCustomizer::Plugins::Plugin
      BaseAction  = ForestAdminDatasourceCustomizer::Decorators::Action::BaseAction
      ActionScope = ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope

      NAMES = { single: 'Trigger payee verification',
                bulk: 'Trigger payee verification on selected accounts' }.freeze

      def run(_datasource_customizer, collection_customizer = nil, options = {})
        datasource = options[:datasource]
        record_id_field = options[:record_id_field]
        raise ArgumentError, 'TriggerPayeeVerification plugin requires :datasource' unless datasource
        raise ArgumentError, 'TriggerPayeeVerification plugin requires :record_id_field' unless record_id_field
        raise ArgumentError, 'TriggerPayeeVerification plugin requires a collection' unless collection_customizer

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
          if ids.empty?
            next result_builder.error(message: "No Mambu external account id found in '#{record_id_field}'.")
          end

          succeeded, failed = Helpers.each_with_rescue(ids, 'verify_external_account') do |id|
            datasource.client.verify_external_account(id)
          end
          finalize(result_builder, succeeded, failed)
        end
      end

      def finalize(result_builder, succeeded, failed)
        if succeeded.empty?
          return result_builder.error(message: Messages.all_failed(failed, noun: 'external account',
                                                                           verb: 'verify'))
        end

        result_builder.success(message: Messages.success(succeeded, failed, noun: 'external account',
                                                                            verb_past: 'now pending verification'))
      end
    end
  end
end
