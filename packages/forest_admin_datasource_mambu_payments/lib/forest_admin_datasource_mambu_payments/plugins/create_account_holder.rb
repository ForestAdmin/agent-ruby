module ForestAdminDatasourceMambuPayments
  module Plugins
    class CreateAccountHolder < ForestAdminDatasourceCustomizer::Plugins::Plugin
      BaseAction  = ForestAdminDatasourceCustomizer::Decorators::Action::BaseAction
      ActionScope = ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope
      FieldType   = ForestAdminDatasourceCustomizer::Decorators::Action::Types::FieldType

      NAME = 'Create Mambu account holder'.freeze

      def run(_datasource_customizer, collection_customizer = nil, options = {})
        datasource = options[:datasource]
        raise ArgumentError, 'CreateAccountHolder plugin requires :datasource' unless datasource
        raise ArgumentError, 'CreateAccountHolder plugin requires a collection' unless collection_customizer

        collection_customizer.add_action(options[:action_name] || NAME, build_action(datasource, options))
      end

      private

      def build_action(datasource, opts)
        BaseAction.new(scope: ActionScope::SINGLE, form: form, &executor(datasource, opts))
      end

      def form
        [{ type: FieldType::STRING, label: 'Name', is_required: true,
           description: 'Display name of the account holder.' }]
      end

      def executor(datasource, opts)
        lambda do |context, result_builder|
          values = context.form_values
          payload = { 'name' => values['Name'] }
          holder = datasource.client.create_account_holder(payload)
          id = holder.is_a?(Hash) ? holder['id'] : nil
          writeback = Helpers.write_back(context, opts[:result_field], id)
          message = id ? "Account holder ##{id} created." : 'Account holder created.'
          result_builder.success(message: "#{message}#{Helpers.write_back_warning(writeback)}")
        end
      end
    end
  end
end
