module ForestAdminDatasourceMambuPayments
  module Plugins
    module SmartActions
      class CreateExternalAccount < ForestAdminDatasourceCustomizer::Plugins::Plugin
        BaseAction  = ForestAdminDatasourceCustomizer::Decorators::Action::BaseAction
        ActionScope = ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope
        FieldType   = ForestAdminDatasourceCustomizer::Decorators::Action::Types::FieldType

        NAME = 'Create Mambu external account'.freeze

        def run(_datasource_customizer, collection_customizer = nil, options = {})
          datasource = options[:datasource]
          raise ArgumentError, 'CreateExternalAccount plugin requires :datasource' unless datasource
          raise ArgumentError, 'CreateExternalAccount plugin requires a collection' unless collection_customizer

          collection_customizer.add_action(options[:action_name] || NAME, build_action(datasource, options))
        end

        private

        def build_action(datasource, opts)
          BaseAction.new(scope: ActionScope::SINGLE, form: form, &executor(datasource, opts))
        end

        def form
          [
            { type: FieldType::STRING, label: 'Holder name', is_required: true,
              description: 'Name of the legal entity or individual holding the account.' },
            { type: FieldType::STRING, label: 'Account number', is_required: true,
              description: 'IBAN, UK account number, or local format.' },
            { type: FieldType::STRING, label: 'Bank code', is_required: true,
              description: 'BIC, UK sort code, US routing number, or local equivalent.' }
          ]
        end

        def executor(datasource, opts)
          lambda do |context, result_builder|
            values = context.form_values
            payload = {
              'holder_name' => values['Holder name'],
              'account_number' => values['Account number'],
              'bank_code' => values['Bank code']
            }
            account = datasource.client.create_external_account(payload)
            id = account.is_a?(Hash) ? account['id'] : nil
            writeback = Helpers.write_back(context, opts[:result_field], id)
            message = id ? "External account ##{id} created." : 'External account created.'
            result_builder.success(message: "#{message}#{Helpers.write_back_warning(writeback)}")
          end
        end
      end
    end
  end
end
