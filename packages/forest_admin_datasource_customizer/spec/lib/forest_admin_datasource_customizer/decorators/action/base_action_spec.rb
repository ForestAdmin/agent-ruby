require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Action
      describe BaseAction do
        let(:scope) { Types::ActionScope::SINGLE }
        let(:field_send_notification) { { label: 'Send a notification', type: 'Boolean', widget: 'Checkbox', is_required: true, default_value: false } }
        let(:field_message) { { label: 'Notification message', type: 'String', is_required: true, default_value: 'Hello' } }
        let(:form) do
          [
            field_send_notification,
            field_message
          ]
        end
        let(:action) { described_class.new(scope: scope, form: form) }

        describe 'when initialize' do
          it 'initializes with correct attributes' do
            expect(action.scope).to eq(scope)
            expect(action.form).to eq(form)
            expect(action.is_generate_file).to be(false)
            expect(action.execute).to be_nil
            expect(action.description).to be_nil
            expect(action.submit_button_label).to be_nil
          end

          it 'set description and submit_button_label when provided' do
            description = 'Send a notification to the user'
            submit_button_label = 'Send notification !'
            action = described_class.new(scope: scope, form: form, description: description, submit_button_label: submit_button_label)
            expect(action.description).to eq(description)
            expect(action.submit_button_label).to eq(submit_button_label)
          end
        end

        describe 'when check form is static' do
          context 'when form is nil' do
            let(:action) { described_class.new(scope: :single) }

            it 'returns true' do
              expect(action.static_form?).to be true
            end
          end

          context 'when all fields are static' do
            let(:form) { [instance_double(DynamicField, static?: true, type: 'String'), instance_double(DynamicField, static?: true, type: 'String')] }
            let(:action) { described_class.new(scope: :single, form: form) }

            it 'returns true' do
              expect(action.static_form?).to be true
            end
          end

          context 'when some fields are not static' do
            let(:form) { [instance_double(DynamicField, static?: true), instance_double(DynamicField, static?: false)] }
            let(:action) { described_class.new(scope: :single, form: form) }

            it 'returns false' do
              expect(action.static_form?).to be false
            end
          end
        end
      end
    end
  end
end
