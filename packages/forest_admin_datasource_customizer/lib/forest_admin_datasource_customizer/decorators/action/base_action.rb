module ForestAdminDatasourceCustomizer
  module Decorators
    module Action
      class BaseAction
        attr_reader :scope, :form, :is_generate_file, :execute

        def initialize(scope:, form: nil, is_generate_file: false, &execute)
          @scope = scope
          @form = form
          @is_generate_file = is_generate_file
          @execute = execute
        end

        def build_elements
          @form = @form&.map do |field|
            if field.key? :widget
              build_widget(field)
            elsif field[:type] == 'Layout'
              build_layout_element(field)
            else
              DynamicField.new(**field)
            end
          end
        end

        def build_widget(field)
          case field[:widget]
          when 'AddressAutocomplete'
            WidgetField::AddressAutocompleteField.new(**field)
          when 'Checkbox'
            WidgetField::CheckboxField.new(**field)
          when 'CheckboxGroup'
            WidgetField::CheckboxGroupField.new(**field)
          when 'ColorPicker'
            WidgetField::ColorPickerField.new(**field)
          when 'CurrencyInput'
            WidgetField::CurrencyInputField.new(**field)
          when 'DatePicker'
            WidgetField::DatePickerField.new(**field)
          when 'Dropdown'
            WidgetField::DropdownField.new(**field)
          when 'FilePicker'
            WidgetField::FilePickerField.new(**field)
          when 'JsonEditor'
            WidgetField::JsonEditorField.new(**field)
          when 'NumberInput'
            WidgetField::NumberInputField.new(**field)
          when 'NumberInputList'
            WidgetField::NumberInputListField.new(**field)
          when 'RadioGroup'
            WidgetField::RadioGroupField.new(**field)
          when 'RichText'
            WidgetField::RichTextField.new(**field)
          when 'TextArea'
            WidgetField::TextAreaField.new(**field)
          when 'TextInput'
            WidgetField::TextInputField.new(**field)
          when 'TextInputList'
            WidgetField::TextInputListField.new(**field)
          when 'TimePicker'
            WidgetField::TimePickerField.new(**field)
          when 'UserDropdown'
            WidgetField::UserDropdownField.new(**field)
          else
            raise ForestAdminDatasourceToolkit::Exceptions::ForestException, "Unknow widget type: #{field[:widget]}"
          end
        end

        def build_layout_element(field)
          case field[:component]
          when 'Separator'
            FormLayoutElement::SeparatorElement.new(**field)
          else
            raise ForestAdminDatasourceToolkit::Exceptions::ForestException,
                  "Unknow component type: #{field[:component]}"
          end
        end

        def static_form?
          return form&.all?(&:static?) if form

          true
        end
      end
    end
  end
end
