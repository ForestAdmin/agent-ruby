module ForestAdminDatasourceMambuPayments
  module Plugins
    class UpdateAccountHolder < ForestAdminDatasourceCustomizer::Plugins::Plugin
      BaseAction  = ForestAdminDatasourceCustomizer::Decorators::Action::BaseAction
      ActionScope = ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope
      FieldType   = ForestAdminDatasourceCustomizer::Decorators::Action::Types::FieldType

      NAME = 'Update Mambu account holder'.freeze

      def run(_datasource_customizer, collection_customizer = nil, options = {})
        datasource = options[:datasource]
        record_id_field = options[:record_id_field]
        raise ArgumentError, 'UpdateAccountHolder plugin requires :datasource' unless datasource
        raise ArgumentError, 'UpdateAccountHolder plugin requires :record_id_field' unless record_id_field
        raise ArgumentError, 'UpdateAccountHolder plugin requires a collection' unless collection_customizer

        collection_customizer.add_action(options[:action_name] || NAME, build_action(datasource, options))
      end

      private

      def build_action(datasource, opts)
        BaseAction.new(scope: ActionScope::SINGLE, form: form, &executor(datasource, opts))
      end

      def form
        [{ type: FieldType::STRING, label: 'Name',
           description: 'New display name (leave empty to keep the current value).' }]
      end

      def executor(datasource, opts)
        lambda do |context, result_builder|
          ids = Helpers.resolve_ids(context, opts[:record_id_field])
          if ids.empty?
            next result_builder.error(message: "No Mambu account holder id found in '#{opts[:record_id_field]}'.")
          end

          payload = build_payload(context.form_values)
          next result_builder.error(message: 'Nothing to update: fill at least one field.') if payload.empty?

          succeeded, failed = Helpers.each_with_rescue(ids, 'update_account_holder') do |id|
            datasource.client.update_account_holder(id, payload)
          end
          finalize(result_builder, succeeded, failed)
        end
      end

      def build_payload(values)
        payload = {}
        payload['name'] = values['Name'] if Helpers.present?(values['Name'])
        payload
      end

      def finalize(result_builder, succeeded, failed)
        if succeeded.empty?
          return result_builder.error(message: Messages.all_failed(failed, noun: 'account holder',
                                                                           verb: 'update'))
        end

        result_builder.success(message: Messages.success(succeeded, failed, noun: 'account holder',
                                                                            verb_past: 'updated'))
      end
    end
  end
end
