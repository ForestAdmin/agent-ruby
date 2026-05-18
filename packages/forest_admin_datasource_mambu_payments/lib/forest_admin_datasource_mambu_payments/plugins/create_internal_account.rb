module ForestAdminDatasourceMambuPayments
  module Plugins
    class CreateInternalAccount < ForestAdminDatasourceCustomizer::Plugins::Plugin
      BaseAction  = ForestAdminDatasourceCustomizer::Decorators::Action::BaseAction
      ActionScope = ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope
      FieldType   = ForestAdminDatasourceCustomizer::Decorators::Action::Types::FieldType

      NAME = 'Create Mambu internal account'.freeze
      TYPES = %w[own virtual].freeze

      def run(_datasource_customizer, collection_customizer = nil, options = {})
        datasource = options[:datasource]
        raise ArgumentError, 'CreateInternalAccount plugin requires :datasource' unless datasource
        raise ArgumentError, 'CreateInternalAccount plugin requires a collection' unless collection_customizer

        collection_customizer.add_action(options[:action_name] || NAME, build_action(datasource, options))
      end

      private

      def build_action(datasource, opts)
        BaseAction.new(scope: ActionScope::SINGLE, form: form, &executor(datasource, opts))
      end

      def form
        [
          { type: FieldType::ENUM, label: 'Type', is_required: true, enum_values: TYPES,
            description: 'own (real bank account) or virtual (sub-account).' },
          { type: FieldType::STRING, label: 'Name', is_required: true,
            description: 'Display name (max 100 characters).' },
          { type: FieldType::STRING, label: 'Holder name', is_required: true,
            description: 'Account holder name (max 100 characters).' },
          { type: FieldType::STRING, label: 'Account number', is_required: true,
            description: 'IBAN or local account number (own); up to 35 alnum chars (virtual).' }
        ]
      end

      def executor(datasource, opts)
        lambda do |context, result_builder|
          values = context.form_values
          payload = {
            'type' => values['Type'],
            'name' => values['Name'],
            'holder_name' => values['Holder name'],
            'account_number' => values['Account number']
          }
          account = datasource.client.create_internal_account(payload)
          id = account.is_a?(Hash) ? account['id'] : nil
          writeback = Helpers.write_back(context, opts[:result_field], id)
          message = id ? "Internal account ##{id} created." : 'Internal account created.'
          result_builder.success(message: "#{message}#{Helpers.write_back_warning(writeback)}")
        end
      end
    end
  end
end
