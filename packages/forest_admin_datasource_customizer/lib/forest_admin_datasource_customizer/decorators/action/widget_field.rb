module ForestAdminDatasourceCustomizer
  module Decorators
    module Action
      module WidgetField
        include Types
        def self.validate_arg(options, attribute, rule)
          case rule[attribute]
          when 'contains'
            unless rule[:value].include? options[attribute]
              raise ForestAdminDatasourceToolkit::Exceptions::ForestException,
                    "'#{attribute}' must have a value included in [#{rule[:value]}]"
            end
          when 'present'
            unless options.key? attribute
              raise ForestAdminDatasourceToolkit::Exceptions::ForestException,
                    "key '#{attribute}' must be defined"
            end
          end
        end

        class TimePickerField < DynamicField
          def initialize(options)
            super(**options)
            WidgetField.validate_arg(options, :type, { type: 'contains', value: ['Time'] })
            @widget = 'TimePicker'
          end
        end

        class AddressAutocompleteField < DynamicField
          attr_reader :placeolder

          def initialize(options)
            super(**options)
            WidgetField.validate_arg(options, :type, { type: 'contains', value: ['String'] })

            @placeolder = options[:placeholder] || nil
            @widget = 'AddressAutocomplete'
          end
        end

        class CheckboxField < DynamicField
          def initialize(options)
            super(**options)
            WidgetField.validate_arg(options, :type, { type: 'contains', value: [FieldType::BOOLEAN] })

            @widget = 'Checkbox'
          end
        end

        class CheckboxGroupField < DynamicField
          def initialize(options)
            super(**options)

            WidgetField.validate_arg(options, :options, { type: 'present' })
            WidgetField.validate_arg(
              options,
              :type,
              { type: 'contains', value: [FieldType::STRING_LIST, FieldType::NUMBER_LIST] }
            )

            @widget = 'CheckboxGroup'
            @options = options[:options]
          end
        end

        class ColorPickerField < DynamicField
          def initialize(options)
            super(**options)

            WidgetField.validate_arg(enable_opac, :type, { type: 'contains', value: [FieldType::STRING] })

            @widget = 'ColorPicker'
            @enable_opacity = options[:enable_opacity] || nil
            @quick_palette = options[:quick_palette] || nil
          end
        end

        class CurrencyInputField < DynamicField
          def initialize(options)
            super(**options)

            WidgetField.validate_arg(options, :type, { type: 'contains', value: [FieldType::NUMBER] })
            WidgetField.validate_arg(options, :currency, { type: 'present' })

            @widget = 'CurrencyInput'
            @currency = options[:currency]
            @base = options[:base] || 'Unit'
            @min = options[:min] || nil
            @max = options[:max] || nil
            @step = options[:step] || nil
          end
        end

        class DatePickerField < DynamicField
          def initialize(options)
            super(**options)

            WidgetField.validate_arg(
              options,
              'type',
              { type: 'contains', value: [FieldType::DATE, FieldType::DATE_ONLY, FieldType::STRING] }
            )

            @widget = 'DatePicker'
            @format = options[:format] || nil
            @min = options[:min] || nil
            @max = options[:max] || nil
            @step = options[:step] || nil
          end
        end

        class DropdownField < DynamicField
          def initialize(options)
            super(**options)
            WidgetField.validate_arg(options, :options, { type: 'present' })
            WidgetField.validate_arg(
              options,
              'type',
              {
                type: 'contains',
                value: [FieldType::DATE, FieldType::DATE_ONLY, FieldType::STRING, FieldType::STRING_LIST]
              }
            )

            @widget = 'Dropdown'
            @options = options[:options]
            @search = options[:search] || nil
          end
        end

        class FilePickerField < DynamicField
          def initialize(options)
            super(**options)
            WidgetField.validate_arg(options, :options, { type: 'present' })
            WidgetField.validate_arg(
              options,
              'type',
              {
                type: 'contains',
                value: [FieldType::FILE, FieldType::FILE_LIST]
              }
            )

            @widget = 'FilePicker'
            @extensions = options[:extensions] || nil
            @max_size_mb = options[:max_size_mb] || nil
            @max_count = options[:max_count] || nil
          end
        end

        class NumberInputField < DynamicField
          def initialize(options)
            super(**options)
            WidgetField.validate_arg(options, :options, { type: 'present' })
            WidgetField.validate_arg(
              options,
              'type',
              {
                type: 'contains',
                value: [FieldType::NUMBER]
              }
            )

            @widget = 'NumberInput'
            @step = options[:step] || nil
            @min = options[:min] || nil
            @max = options[:max] || nil
          end
        end

        class JsonEditorField < DynamicField
          def initialize(options)
            super(**options)
            WidgetField.validate_arg(
              options,
              'type',
              {
                type: 'contains',
                value: [FieldType::DATE, FieldType::DATE_ONLY, FieldType::STRING, FieldType::STRING_LIST]
              }
            )

            @widget = 'JsonEditor'
          end
        end

        class NumberListInputField < DynamicField
          def initialize(options)
            super(**options)
            WidgetField.validate_arg(options, :options, { type: 'present' })
            WidgetField.validate_arg(
              options,
              'type',
              {
                type: 'contains',
                value: [FieldType::NUMBER_LIST]
              }
            )

            @widget = 'NumberList'
            @allow_duplicates = options[:allow_duplicates] || nil
            @allow_empty_values = options[:allow_empty_values] || nil
            @enable_reorder = options[:enable_reorder] || nil
            @min = options[:min] || nil
            @max = options[:max] || nil
            @step = options[:step] || nil
          end
        end

        class RadioGroupField < DynamicField
          def initialize(options)
            super(**options)
            WidgetField.validate_arg(options, :options, { type: 'present' })
            WidgetField.validate_arg(
              options,
              'type',
              {
                type: 'contains',
                value: [FieldType::DATE, FieldType::DATEONLY, FieldType::NUMBER, FieldType::STRING]
              }
            )

            @widget = 'RadioGroup'
            @options = options[:options]
          end
        end

        class RichTextField < DynamicField
          def initialize(options)
            super(**options)
            WidgetField.validate_arg(options, :options, { type: 'present' })
            WidgetField.validate_arg(
              options,
              'type',
              {
                type: 'contains',
                value: [FieldType::STRING]
              }
            )

            @widget = 'RichText'
          end
        end

        class TextAreaField < DynamicField
          def initialize(options)
            super(**options)
            WidgetField.validate_arg(
              options,
              'type',
              {
                type: 'contains',
                value: [FieldType::STRING]
              }
            )

            @widget = 'RichText'
            @rows = options[:rows] || nil
          end
        end

        class TextInputField < DynamicField
          def initialize(options)
            super(**options)
            WidgetField.validate_arg(
              options,
              'type',
              {
                type: 'contains',
                value: [FieldType::STRING]
              }
            )

            @widget = 'TextInput'
          end
        end

        class TextInputListField < DynamicField
          def initialize(options)
            super(**options)
            WidgetField.validate_arg(
              options,
              'type',
              {
                type: 'contains',
                value: [FieldType::STRING_LIST]
              }
            )

            @widget = 'TextInput'
            @allow_duplicates = options[:allow_duplicates] || nil
            @allow_empty_values = options[:allow_empty_values] || nil
            @enable_reorder = options[:enable_reorder] || nil
          end
        end

        class UserDropdownField < DynamicField
          def initialize(options)
            super(**options)
            WidgetField.validate_arg(options, :options, { type: 'present' })
            WidgetField.validate_arg(
              options,
              'type',
              {
                type: 'contains',
                value: [FieldType::STRING, FieldType::STRING_LIST]
              }
            )

            @widget = 'Dropdown'
          end
        end
      end
    end
  end
end
