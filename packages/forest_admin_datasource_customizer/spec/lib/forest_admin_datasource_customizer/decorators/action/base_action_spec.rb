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

        describe 'when build_widget' do
          it 'returns a CheckboxField for widget type "Checkbox"' do
            result = action.build_widget(field_send_notification)
            expect(result).to be_a(WidgetField::CheckboxField)
          end

          it 'raises an exception for an unknown widget type' do
            field = { widget: 'UnknownWidget' }
            expect { action.build_widget(field) }.to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException)
          end

          context 'when widget is AddressAutocomplete' do
            let(:field) { { label: 'foo', widget: 'AddressAutocomplete', type: 'String' } }

            it 'returns an AddressAutocompleteField' do
              result = action.build_widget(field)
              expect(result).to be_a(ForestAdminDatasourceCustomizer::Decorators::Action::WidgetField::AddressAutocompleteField)
              expect(result.widget).to eq('AddressAutocomplete')
            end
          end

          context 'when widget is CheckboxGroup' do
            let(:field) { { label: 'foo', widget: 'CheckboxGroup', type: 'StringList', options: [] } }

            it 'returns a CheckboxGroupField' do
              result = action.build_widget(field)
              expect(result).to be_a(ForestAdminDatasourceCustomizer::Decorators::Action::WidgetField::CheckboxGroupField)
              expect(result.widget).to eq('CheckboxGroup')
            end
          end

          context 'when widget is ColorPicker' do
            let(:field) { { label: 'foo', widget: 'ColorPicker', type: 'base_', enable_opacity: true } }

            it 'returns a ColorPickerField' do
              result = action.build_widget(field)
              expect(result).to be_a(ForestAdminDatasourceCustomizer::Decorators::Action::WidgetField::ColorPickerField)
              expect(result.widget).to eq('ColorPicker')
            end
          end

          context 'when widget is CurrencyInput' do
            let(:field) { { label: 'foo', widget: 'CurrencyInput', type: 'Number', currency: 'USD' } }

            it 'returns a CurrencyInputField' do
              result = action.build_widget(field)
              expect(result).to be_a(ForestAdminDatasourceCustomizer::Decorators::Action::WidgetField::CurrencyInputField)
              expect(result.widget).to eq('CurrencyInput')
            end
          end

          context 'when widget is DatePicker' do
            let(:field) { { label: 'foo', widget: 'DatePicker', type: 'Date' } }

            it 'returns a DatePickerField' do
              result = action.build_widget(field)
              expect(result).to be_a(ForestAdminDatasourceCustomizer::Decorators::Action::WidgetField::DatePickerField)
              expect(result.widget).to eq('DatePicker')
            end
          end

          context 'when widget is Dropdown' do
            let(:field) { { label: 'foo', widget: 'Dropdown', type: 'String', options: [] } }

            it 'returns a DropdownField' do
              result = action.build_widget(field)
              expect(result).to be_a(ForestAdminDatasourceCustomizer::Decorators::Action::WidgetField::DropdownField)
              expect(result.widget).to eq('Dropdown')
            end
          end

          context 'when widget is FilePicker' do
            let(:field) { { label: 'foo', widget: 'FilePicker', type: 'File', options: [] } }

            it 'returns a FilePickerField' do
              result = action.build_widget(field)
              expect(result).to be_a(ForestAdminDatasourceCustomizer::Decorators::Action::WidgetField::FilePickerField)
              expect(result.widget).to eq('FilePicker')
            end
          end

          context 'when widget is JsonEditor' do
            let(:field) { { label: 'foo', widget: 'JsonEditor', type: 'String' } }

            it 'returns a JsonEditorField' do
              result = action.build_widget(field)
              expect(result).to be_a(ForestAdminDatasourceCustomizer::Decorators::Action::WidgetField::JsonEditorField)
              expect(result.widget).to eq('JsonEditor')
            end
          end

          context 'when widget is NumberInput' do
            let(:field) { { label: 'foo', widget: 'NumberInput', type: 'Number' } }

            it 'returns a NumberInputField' do
              result = action.build_widget(field)
              expect(result).to be_a(ForestAdminDatasourceCustomizer::Decorators::Action::WidgetField::NumberInputField)
              expect(result.widget).to eq('NumberInput')
            end
          end

          context 'when widget is NumberInputList' do
            let(:field) { { label: 'foo', widget: 'NumberInputList', type: 'NumberList', options: [] } }

            it 'returns a NumberInputListField' do
              result = action.build_widget(field)
              expect(result).to be_a(ForestAdminDatasourceCustomizer::Decorators::Action::WidgetField::NumberInputListField)
              expect(result.widget).to eq('NumberInputList')
            end
          end

          context 'when widget is RadioGroup' do
            let(:field) { { label: 'foo', widget: 'RadioGroup', type: 'Number', options: [] } }

            it 'returns a RadioGroupField' do
              result = action.build_widget(field)
              expect(result).to be_a(ForestAdminDatasourceCustomizer::Decorators::Action::WidgetField::RadioGroupField)
              expect(result.widget).to eq('RadioGroup')
            end
          end

          context 'when widget is RichText' do
            let(:field) { { label: 'foo', widget: 'RichText', type: 'String' } }

            it 'returns a RichTextField' do
              result = action.build_widget(field)
              expect(result).to be_a(ForestAdminDatasourceCustomizer::Decorators::Action::WidgetField::RichTextField)
              expect(result.widget).to eq('RichText')
            end
          end

          context 'when widget is TextArea' do
            let(:field) { { label: 'foo', widget: 'TextArea', type: 'String' } }

            it 'returns a TextAreaField' do
              result = action.build_widget(field)
              expect(result).to be_a(ForestAdminDatasourceCustomizer::Decorators::Action::WidgetField::TextAreaField)
              expect(result.widget).to eq('TextArea')
            end
          end

          context 'when widget is TextInput' do
            let(:field) { { label: 'foo', widget: 'TextInput', type: 'String' } }

            it 'returns a TextInputField' do
              result = action.build_widget(field)
              expect(result).to be_a(ForestAdminDatasourceCustomizer::Decorators::Action::WidgetField::TextInputField)
              expect(result.widget).to eq('TextInput')
            end
          end

          context 'when widget is TextInputList' do
            let(:field) { { label: 'foo', widget: 'TextInputList', type: 'StringList', options: [] } }

            it 'returns a TextInputListField' do
              result = action.build_widget(field)
              expect(result).to be_a(ForestAdminDatasourceCustomizer::Decorators::Action::WidgetField::TextInputListField)
              expect(result.widget).to eq('TextInputList')
            end
          end

          context 'when widget is TimePicker' do
            let(:field) { { label: 'foo', widget: 'TimePicker', type: 'Time' } }

            it 'returns a TimePickerField' do
              result = action.build_widget(field)
              expect(result).to be_a(ForestAdminDatasourceCustomizer::Decorators::Action::WidgetField::TimePickerField)
              expect(result.widget).to eq('TimePicker')
            end
          end

          context 'when widget is UserDropdown' do
            let(:field) { { label: 'foo', widget: 'UserDropdown', type: 'String', options: [] } }

            it 'returns a UserDropdownField' do
              result = action.build_widget(field)
              expect(result).to be_a(ForestAdminDatasourceCustomizer::Decorators::Action::WidgetField::UserDropdownField)
              expect(result.widget).to eq('UserDropdown')
            end
          end
        end

        describe 'when build_layout_element' do
          context 'when element is a separator' do
            let(:element) { { type: 'Layout', component: 'Separator' } }

            it 'returns a separator element' do
              result = action.build_layout_element(element)
              expect(result).to be_a(ForestAdminDatasourceCustomizer::Decorators::Action::FormLayoutElement::SeparatorElement)
            end
          end

          context 'when element is a HtmlBlock' do
            let(:element) { { type: 'Layout', component: 'HtmlBlock', content: '<p>foo</p>' } }

            it 'returns a html block element' do
              result = action.build_layout_element(element)
              expect(result).to be_a(ForestAdminDatasourceCustomizer::Decorators::Action::FormLayoutElement::HtmlBlockElement)
              expect(result.content).to eq('<p>foo</p>')
            end
          end

          context 'when element is a Row' do
            let(:element) { { type: 'Layout', component: 'Row', fields: [field_send_notification, field_message] } }

            it 'returns a row element' do
              result = action.build_layout_element(element)
              expect(result).to be_a(ForestAdminDatasourceCustomizer::Decorators::Action::FormLayoutElement::RowElement)
              expect(result.fields[0].label).to eq('Send a notification')
              expect(result.fields[1].label).to eq('Notification message')
            end

            it 'raises an exception when fields are missing' do
              element.delete(:fields)
              expect { action.build_layout_element(element) }.to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException)
            end

            it 'raises an exception when fields contain a layout element' do
              element[:fields] << { type: 'Layout' }
              expect { action.build_layout_element(element) }.to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException)
            end
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
