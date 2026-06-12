module ForestAdminDatasourceMambuPayments
  module Plugins
    module SmartActions
      class UpdateExternalAccount < ForestAdminDatasourceCustomizer::Plugins::Plugin
        BaseAction  = ForestAdminDatasourceCustomizer::Decorators::Action::BaseAction
        ActionScope = ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope
        FieldType   = ForestAdminDatasourceCustomizer::Decorators::Action::Types::FieldType

        NAME = 'Update Mambu external account'.freeze

        def run(_datasource_customizer, collection_customizer = nil, options = {})
          datasource = options[:datasource]
          record_id_field = options[:record_id_field]
          raise ArgumentError, 'UpdateExternalAccount plugin requires :datasource' unless datasource
          raise ArgumentError, 'UpdateExternalAccount plugin requires :record_id_field' unless record_id_field
          raise ArgumentError, 'UpdateExternalAccount plugin requires a collection' unless collection_customizer

          collection_customizer.add_action(options[:action_name] || NAME, build_action(datasource, options))
        end

        private

        def build_action(datasource, opts)
          BaseAction.new(scope: ActionScope::SINGLE, form: form, &executor(datasource, opts))
        end

        def form
          [
            { type: FieldType::STRING, label: 'Holder name',
              description: 'Leave empty to keep the current value.' },
            { type: FieldType::STRING, label: 'Account number',
              description: 'Leave empty to keep the current value.' },
            { type: FieldType::STRING, label: 'Bank code',
              description: 'Leave empty to keep the current value.' }
          ]
        end

        def executor(datasource, opts)
          lambda do |context, result_builder|
            ids = Helpers.resolve_ids(context, opts[:record_id_field])
            if ids.empty?
              next result_builder.error(message: "No Mambu external account id found in '#{opts[:record_id_field]}'.")
            end

            payload = build_payload(context.form_values)
            next result_builder.error(message: 'Nothing to update: fill at least one field.') if payload.empty?

            succeeded, failed = Helpers.each_with_rescue(ids, 'update_external_account') do |id|
              datasource.client.update_external_account(id, payload)
            end
            finalize(result_builder, succeeded, failed)
          end
        end

        def build_payload(values)
          payload = {}
          payload['holder_name']    = values['Holder name']    if Helpers.present?(values['Holder name'])
          payload['account_number'] = values['Account number'] if Helpers.present?(values['Account number'])
          payload['bank_code']      = values['Bank code']      if Helpers.present?(values['Bank code'])
          payload
        end

        def finalize(result_builder, succeeded, failed)
          if succeeded.empty?
            return result_builder.error(message: Messages.all_failed(failed, noun: 'external account',
                                                                             verb: 'update'))
          end

          result_builder.success(message: Messages.success(succeeded, failed, noun: 'external account',
                                                                              verb_past: 'updated'))
        end
      end
    end
  end
end
