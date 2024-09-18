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
          attr_accessor :widget

          def initialize(options)
            super(**options)
            WidgetField.validate_arg(options, :type, { type: 'contains', value: ['Time'] })
            @widget = 'TimePicker'
          end
        end

        class AddressAutocompleteField < DynamicField
          attr_accessor :widget

          def initialize(options)
            super(**options)
            WidgetField.validate_arg(options, :type, { type: 'contains', value: ['String'] })

            @widget = 'AddressAutocomplete'
          end
        end

        class CheckboxField < DynamicField
          attr_accessor :widget

          def initialize(options)
            super(**options)
            WidgetField.validate_arg(
              options,
              :type,
              { type: 'contains', value: [Types::FieldType::BOOLEAN] }
            )

            @widget = 'Checkbox'
          end
        end

        class CheckboxGroupField < DynamicField
          attr_accessor :widget, :options

          def initialize(options)
            super(**options)

            WidgetField.validate_arg(options, :options, { type: 'present' })
            WidgetField.validate_arg(
              options,
              :type,
              { type: 'contains', value: [Types::FieldType::STRING_LIST, Types::FieldType::NUMBER_LIST] }
            )

            @widget = 'CheckboxGroup'
            @options = options[:options]
          end
        end

        class ColorPickerField < DynamicField
          attr_accessor :widget, :enable_opacity, :quick_palette

          def initialize(options)
            super(**options)

            WidgetField.validate_arg(options, :enable_opacity, { type: 'contains', value: [Types::FieldType::STRING] })

            @widget = 'ColorPicker'
            @enable_opacity = options[:enable_opacity] || nil
            @quick_palette = options[:quick_palette] || nil
          end
        end

        class CurrencyInputField < DynamicField
          attr_accessor :widget, :currency, :base, :min, :max, :step

          def initialize(options)
            super(**options)

            WidgetField.validate_arg(options, :type, { type: 'contains', value: [Types::FieldType::NUMBER] })
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
          attr_accessor :widget, :min, :max, :format, :step

          def initialize(options)
            super(**options)

            WidgetField.validate_arg(
              options,
              'type',
              { type: 'contains',
                value: [Types::FieldType::DATE, Types::FieldType::DATE_ONLY, Types::FieldType::STRING] }
            )

            @widget = 'DatePicker'
            @format = options[:format] || nil
            @min = options[:min] || nil
            @max = options[:max] || nil
            @step = options[:step] || nil
          end
        end

        class DropdownField < DynamicField
          attr_accessor :widget, :options, :search

          def initialize(options)
            super(**options)
            WidgetField.validate_arg(options, :options, { type: 'present' })
            WidgetField.validate_arg(
              options,
              'type',
              {
                type: 'contains',
                value: [Types::FieldType::DATE, Types::FieldType::DATE_ONLY, Types::FieldType::STRING,
                        Types::FieldType::STRING_LIST]
              }
            )

            @widget = 'Dropdown'
            @options = options[:options]
            @search = options[:search] || nil
          end
        end

        class FilePickerField < DynamicField
          attr_accessor :widget, :extensions, :max_count, :max_size_mb

          def initialize(options)
            super(**options)
            WidgetField.validate_arg(options, :options, { type: 'present' })
            WidgetField.validate_arg(
              options,
              'type',
              {
                type: 'contains',
                value: [Types::FieldType::FILE, Types::FieldType::FILE_LIST]
              }
            )

            @widget = 'FilePicker'
            @extensions = options[:extensions] || nil
            @max_size_mb = options[:max_size_mb] || nil
            @max_count = options[:max_count] || nil
          end
        end

        class NumberInputField < DynamicField
          attr_accessor :widget, :step, :min, :max

          def initialize(options)
            super(**options)
            WidgetField.validate_arg(options, :options, { type: 'present' })
            WidgetField.validate_arg(
              options,
              'type',
              {
                type: 'contains',
                value: [Types::FieldType::NUMBER]
              }
            )

            @widget = 'NumberInput'
            @step = options[:step] || nil
            @min = options[:min] || nil
            @max = options[:max] || nil
          end
        end

        class JsonEditorField < DynamicField
          attr_accessor :widget

          def initialize(options)
            super(**options)
            WidgetField.validate_arg(
              options,
              'type',
              {
                type: 'contains',
                value: [Types::FieldType::DATE, Types::FieldType::DATE_ONLY, Types::FieldType::STRING,
                        Types::FieldType::STRING_LIST]
              }
            )

            @widget = 'JsonEditor'
          end
        end

        class NumberInputListField < DynamicField
          attr_accessor :widget, :allow_duplicates, :allow_empty_values, :enable_reorder, :min, :max, :step

          def initialize(options)
            super(**options)
            WidgetField.validate_arg(options, :options, { type: 'present' })
            WidgetField.validate_arg(
              options,
              'type',
              {
                type: 'contains',
                value: [Types::FieldType::NUMBER_LIST]
              }
            )

            @widget = 'NumberInputList'
            @allow_duplicates = options[:allow_duplicates] || nil
            @allow_empty_values = options[:allow_empty_values] || nil
            @enable_reorder = options[:enable_reorder] || nil
            @min = options[:min] || nil
            @max = options[:max] || nil
            @step = options[:step] || nil
          end
        end

        class RadioGroupField < DynamicField
          attr_accessor :widget, :options

          def initialize(options)
            super(**options)
            WidgetField.validate_arg(options, :options, { type: 'present' })
            WidgetField.validate_arg(
              options,
              'type',
              {
                type: 'contains',
                value: [Types::FieldType::DATE, Types::FieldType::DATE_ONLY, Types::FieldType::NUMBER,
                        Types::FieldType::STRING]
              }
            )

            @widget = 'RadioGroup'
            @options = options[:options]
          end
        end

        class RichTextField < DynamicField
          attr_accessor :widget

          def initialize(options)
            super(**options)
            WidgetField.validate_arg(options, :options, { type: 'present' })
            WidgetField.validate_arg(
              options,
              'type',
              {
                type: 'contains',
                value: [Types::FieldType::STRING]
              }
            )

            @widget = 'RichText'
          end
        end

        class TextAreaField < DynamicField
          attr_accessor :widget, :rows

          def initialize(options)
            super(**options)
            WidgetField.validate_arg(
              options,
              'type',
              {
                type: 'contains',
                value: [Types::FieldType::STRING]
              }
            )

            @widget = 'TextArea'
            @rows = options[:rows] || nil
          end
        end

        class TextInputField < DynamicField
          attr_accessor :widget

          def initialize(options)
            super(**options)
            WidgetField.validate_arg(
              options,
              'type',
              {
                type: 'contains',
                value: [Types::FieldType::STRING]
              }
            )

            @widget = 'TextInput'
          end
        end

        class TextInputListField < DynamicField
          attr_accessor :widget, :allow_duplicates, :allow_empty_values, :enable_reorder

          def initialize(options)
            super(**options)
            WidgetField.validate_arg(
              options,
              'type',
              {
                type: 'contains',
                value: [Types::FieldType::STRING_LIST]
              }
            )

            @widget = 'TextInputList'
            @allow_duplicates = options[:allow_duplicates] || nil
            @allow_empty_values = options[:allow_empty_values] || nil
            @enable_reorder = options[:enable_reorder] || nil
          end
        end

        class UserDropdownField < DynamicField
          attr_accessor :widget

          def initialize(options)
            super(**options)
            WidgetField.validate_arg(options, :options, { type: 'present' })
            WidgetField.validate_arg(
              options,
              'type',
              {
                type: 'contains',
                value: [Types::FieldType::STRING, Types::FieldType::STRING_LIST]
              }
            )

            @widget = 'UserDropdown'
          end
        end

        class Separator < DynamicField
          @component = 'Separator'
        end
      end
    end
  end
end
