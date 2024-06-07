module ForestAdminAgent
  module Utils
    module Schema
      class ActionFields
        def self.collection_field?(field)
          field&.type == 'Collection'
        end

        def self.enum_field?(field)
          field&.type == 'Enum'
        end

        def self.enum_list_field?(field)
          field&.type == 'EnumList'
        end

        def self.file_field?(field)
          field&.type == 'File'
        end

        def self.file_list_field?(field)
          field&.type == 'FileList'
        end

        def self.dropdown_field?(field)
          field&.widget == 'Dropdown'
        end

        def self.radio_group_field?(field)
          field&.widget == 'RadioGroup'
        end

        def self.checkbox_group_field?(field)
          field&.widget == 'CheckboxGroup'
        end

        def self.checkbox_field?(field)
          field&.widget == 'Checkbox'
        end

        def self.text_input_field?(field)
          field&.widget == 'TextInput'
        end

        def self.date_picker_field?(field)
          field&.widget == 'DatePicker'
        end

        def self.file_picker_field?(field)
          field&.widget == 'FilePicker'
        end

        def self.text_input_list_field?(field)
          field&.widget == 'TextInputList'
        end

        def self.text_area_field?(field)
          field&.widget == 'TextArea'
        end

        def self.rich_text_field?(field)
          field&.widget == 'RichText'
        end

        def self.number_input_field?(field)
          field&.widget == 'NumberInput'
        end

        def self.color_picker_field?(field)
          field&.widget == 'ColorPicker'
        end

        def self.number_input_list_field?(field)
          field&.widget == 'NumberInputList'
        end

        def self.currency_input_field?(field)
          field&.widget == 'CurrencyInput'
        end

        def self.user_dropdown_field?(field)
          field&.widget == 'UserDropdown'
        end

        def self.json_editor_field?(field)
          field&.widget == 'JsonEditor'
        end

        def self.address_autocomplete_field?(field)
          field&.widget == 'AddressAutocomplete'
        end

        def self.time_picker_field?(field)
          field&.widget == 'TimePicker'
        end

        def self.widget?(field)
          !field&.widget.nil?
        end
      end
    end
  end
end
