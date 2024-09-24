module ForestAdminDatasourceToolkit
  module Components
    module Actions
      class ActionFieldFactory
        def self.build(field)
          if field.key? :widget
            build_widget(field)
          elsif field[:type] == 'Layout'
            build_layout_element(field)
          else
            ActionField.new(**field)
          end
        end

        def self.build_layout_element(field)
          case field[:component]
          when 'Separator'
            ActionLayoutElement::SeparatorElement.new(**field)
          when 'HtmlBlock'
            ActionLayoutElement::HtmlBlockElement.new(**field)
          when 'Row'
            return ActionLayoutElement::RowElement.new(**field) unless field[:fields].empty?

            nil
          when 'Page'
            # is it nullable if no elements ???
            ActionLayoutElement::PageElement.new(**field)
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
          end
        end
      end
    end
  end
end
