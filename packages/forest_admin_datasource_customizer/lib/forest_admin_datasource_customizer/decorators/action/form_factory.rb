module ForestAdminDatasourceCustomizer
  module Decorators
    module Action
      class FormFactory
        def self.build_elements(form)
          form&.map do |field|
            case field
            when Hash
              if field.key?(:widget) && !field[:widget].nil?
                build_widget(field)
              elsif field[:type] == 'Layout'
                build_layout_element(field)
              else
                DynamicField.new(**field.transform_keys(&:to_sym))
              end
            when FormLayoutElement::RowElement
              field.fields = build_elements(field.fields)
              field
            when FormLayoutElement::PageElement
              field.elements = build_elements(field.elements)
              field
            else
              field
            end
          end
        end

        def self.build_widget(field)
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
            raise ForestAdminAgent::Http::Exceptions::BadRequestError, "Unknow widget type: #{field[:widget]}"
          end
        end

        def self.build_layout_element(field)
          case field[:component]
          when 'Separator'
            FormLayoutElement::SeparatorElement.new(**field)
          when 'HtmlBlock'
            FormLayoutElement::HtmlBlockElement.new(**field)
          when 'Row'
            FormLayoutElement::RowElement.new(**field)
          when 'Page'
            FormLayoutElement::PageElement.new(**field)
          else
            raise ForestAdminAgent::Http::Exceptions::BadRequestError, "Unknow component type: #{field[:component]}"
          end
        end
      end
    end
  end
end
