# frozen_string_literal: true

# rubocop:disable RSpec/VerifiedDoubleReference, Style/StringLiterals

require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module DSL
    describe ActionBuilder do
      describe '#initialize' do
        it 'accepts symbol scopes' do
          builder = described_class.new(scope: :single)
          action = builder.instance_eval do
            execute { success 'OK' }
            to_action
          end

          expect(action.scope).to eq(Decorators::Action::Types::ActionScope::SINGLE)
        end

        it 'normalizes scope symbols' do
          {
            single: Decorators::Action::Types::ActionScope::SINGLE,
            bulk: Decorators::Action::Types::ActionScope::BULK,
            global: Decorators::Action::Types::ActionScope::GLOBAL
          }.each do |symbol, constant|
            builder = described_class.new(scope: symbol)
            action = builder.instance_eval do
              execute { success 'OK' }
              to_action
            end

            expect(action.scope).to eq(constant)
          end
        end

        it 'raises error for invalid scope' do
          expect do
            described_class.new(scope: :invalid)
          end.to raise_error(ArgumentError, /Invalid scope/)
        end
      end

      describe '#description' do
        it 'sets action description' do
          builder = described_class.new(scope: :single)
          action = builder.instance_eval do
            description 'Test action'
            execute { success 'OK' }
            to_action
          end

          expect(action.description).to eq('Test action')
        end
      end

      describe '#submit_button_label' do
        it 'sets custom submit button label' do
          builder = described_class.new(scope: :single)
          action = builder.instance_eval do
            submit_button_label 'Do it!'
            execute { success 'OK' }
            to_action
          end

          expect(action.submit_button_label).to eq('Do it!')
        end
      end

      describe '#generates_file!' do
        it 'marks action as generating file' do
          builder = described_class.new(scope: :global)
          action = builder.instance_eval do
            generates_file!
            execute { file content: 'data', name: 'export.csv' }
            to_action
          end

          expect(action.is_generate_file).to be true
        end
      end

      describe '#form' do
        it 'builds form fields using FormBuilder' do
          builder = described_class.new(scope: :single)
          action = builder.instance_eval do
            form do
              field :name, type: :string
              field :age, type: :number
            end
            execute { success 'OK' }
            to_action
          end

          expect(action.form).to be_an(Array)
          expect(action.form.length).to eq(2)
          expect(action.form[0][:label]).to eq('name')
          expect(action.form[0][:type]).to eq('String')
          expect(action.form[1][:label]).to eq('age')
          expect(action.form[1][:type]).to eq('Number')
        end

        it 'supports complex form structures' do
          builder = described_class.new(scope: :single)
          action = builder.instance_eval do
            form do
              field :email, type: :string, widget: 'TextInput'
              field :country, type: :string, widget: 'Dropdown',
                              options: [{ label: 'US', value: 'us' }]

              page do
                field :address, type: :string
                field :city, type: :string
              end
            end
            execute { success 'OK' }
            to_action
          end

          expect(action.form.length).to eq(3)
          expect(action.form[0][:widget]).to eq('TextInput')
          expect(action.form[1][:options]).to eq([{ label: 'US', value: 'us' }])
          expect(action.form[2][:type]).to eq('Layout')
          expect(action.form[2][:elements].length).to eq(2)
        end
      end

      describe '#execute' do
        it 'wraps execution block with ExecutionContext' do
          builder = described_class.new(scope: :single)
          action = builder.instance_eval do
            execute do
              success 'Action completed successfully'
            end
            to_action
          end

          context = instance_spy("ActionContext")
          result_builder = instance_spy("ResultBuilder")
          expected_result = { type: 'Success', message: 'Action completed successfully' }

          allow(result_builder).to receive(:success).with(
            message: 'Action completed successfully',
            options: {}
          ).and_return(expected_result)

          result = action.execute.call(context, result_builder)
          expect(result).to eq(expected_result)
        end

        it 'provides access to form values' do
          builder = described_class.new(scope: :single)
          action = builder.instance_eval do
            form do
              field :email, type: :string
            end

            execute do
              email = form_value(:email)
              success "Email: #{email}"
            end
            to_action
          end

          context = instance_spy("ActionContext")
          result_builder = instance_spy("ResultBuilder")

          allow(context).to receive(:form_value).with('email').and_return('test@example.com')
          allow(result_builder).to receive(:success).with(
            message: 'Email: test@example.com',
            options: {}
          ).and_return({ type: 'Success' })

          result = action.execute.call(context, result_builder)
          expect(result).to eq({ type: 'Success' })
        end
      end

      describe '#to_action' do
        it 'raises error without execute block' do
          builder = described_class.new(scope: :single)

          expect do
            builder.to_action
          end.to raise_error(ArgumentError, 'execute block is required')
        end

        it 'creates BaseAction with all attributes' do
          builder = described_class.new(scope: :global)
          action = builder.instance_eval do
            description 'Export data'
            submit_button_label 'Export Now'
            generates_file!
            form do
              field :format, type: :string
            end
            execute { file content: 'data', name: 'export.csv' }
            to_action
          end

          expect(action).to be_a(Decorators::Action::BaseAction)
          expect(action.scope).to eq(Decorators::Action::Types::ActionScope::GLOBAL)
          expect(action.description).to eq('Export data')
          expect(action.submit_button_label).to eq('Export Now')
          expect(action.is_generate_file).to be true
          expect(action.form).to be_an(Array)
          expect(action.execute).to be_a(Proc)
        end
      end
    end
  end
end

# rubocop:enable RSpec/VerifiedDoubleReference, Style/StringLiterals
