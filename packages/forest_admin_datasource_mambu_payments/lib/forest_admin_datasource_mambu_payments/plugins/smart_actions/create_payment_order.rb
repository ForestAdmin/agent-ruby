module ForestAdminDatasourceMambuPayments
  module Plugins
    module SmartActions
      class CreatePaymentOrder < ForestAdminDatasourceCustomizer::Plugins::Plugin
        BaseAction  = ForestAdminDatasourceCustomizer::Decorators::Action::BaseAction
        ActionScope = ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope
        FieldType   = ForestAdminDatasourceCustomizer::Decorators::Action::Types::FieldType

        NAME = 'Create Mambu payment order'.freeze
        DIRECTIONS = %w[credit debit].freeze

        def run(_datasource_customizer, collection_customizer = nil, options = {})
          datasource = options[:datasource]
          raise ArgumentError, 'CreatePaymentOrder plugin requires :datasource' unless datasource
          raise ArgumentError, 'CreatePaymentOrder plugin requires a collection' unless collection_customizer

          collection_customizer.add_action(options[:action_name] || NAME, build_action(datasource, options))
        end

        private

        def build_action(datasource, opts)
          BaseAction.new(scope: ActionScope::SINGLE, form: form, &executor(datasource, opts))
        end

        def form
          [
            { type: FieldType::STRING, label: 'Type', is_required: true,
              description: 'Payment type (e.g. sepa_credit_transfer, swift). See Numeral docs for the full list.' },
            { type: FieldType::ENUM, label: 'Direction', is_required: true, enum_values: DIRECTIONS },
            { type: FieldType::NUMBER, label: 'Amount', is_required: true,
              description: "Amount in the currency's smallest unit (e.g. cents for EUR)." },
            { type: FieldType::STRING, label: 'Currency', is_required: true,
              description: 'ISO 4217 code (e.g. EUR, USD).' },
            { type: FieldType::STRING, label: 'Reference', is_required: true,
              description: 'Reference shown on the account statements (max 140 characters).' },
            { type: FieldType::STRING, label: 'Connected account id', is_required: true,
              description: 'UUID of the connected account that triggers the payment.' }
          ]
        end

        def executor(datasource, opts)
          lambda do |context, result_builder|
            values = context.form_values
            amount = Helpers.to_int(values['Amount'])
            next result_builder.error(message: 'Amount must be an integer (smallest currency unit).') unless amount

            payload = {
              'type' => values['Type'],
              'direction' => values['Direction'],
              'amount' => amount,
              'currency' => values['Currency'],
              'reference' => values['Reference'],
              'connected_account_id' => values['Connected account id']
            }
            order = datasource.client.create_payment_order(payload)
            id = order.is_a?(Hash) ? order['id'] : nil
            writeback = Helpers.write_back(context, opts[:result_field], id)
            message = id ? "Payment order ##{id} created." : 'Payment order created.'
            result_builder.success(message: "#{message}#{Helpers.write_back_warning(writeback)}")
          end
        end
      end
    end
  end
end
