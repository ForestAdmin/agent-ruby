module ForestAdminDatasourceToolkit
  module Components
    module Actions
      module WidgetField
        class TimePickerField < ActionField
          attr_accessor :widget

          def initialize(options)
            super(**options)
            @widget = 'TimePicker'
          end
        end

        class AddressAutocompleteField < ActionField
          attr_accessor :widget

          def initialize(options)
            super(**options)
            @widget = 'AddressAutocomplete'
          end
        end

        class CheckboxField < ActionField
          attr_accessor :widget

          def initialize(options)
            super(**options)
            @widget = 'Checkbox'
          end
        end

        class CheckboxGroupField < ActionField
          attr_accessor :widget, :options

          def initialize(options)
            super(**options)
            @widget = 'CheckboxGroup'
            @options = options[:options]
          end
        end

        class ColorPickerField < ActionField
          attr_accessor :widget, :enable_opacity, :quick_palette

          def initialize(options)
            super(**options)
            @widget = 'ColorPicker'
            @enable_opacity = options[:enable_opacity] || nil
            @quick_palette = options[:quick_palette] || nil
          end
        end

        class CurrencyInputField < ActionField
          attr_accessor :widget, :currency, :base, :min, :max, :step

          def initialize(options)
            super(**options)
            @widget = 'CurrencyInput'
            @currency = options[:currency]
            @base = options[:base] || 'Unit'
            @min = options[:min] || nil
            @max = options[:max] || nil
            @step = options[:step] || nil
          end
        end

        class DatePickerField < ActionField
          attr_accessor :widget, :min, :max, :format, :step

          def initialize(options)
            super(**options)
            @widget = 'DatePicker'
            @format = options[:format] || nil
            @min = options[:min] || nil
            @max = options[:max] || nil
            @step = options[:step] || nil
          end
        end

        class DropdownField < ActionField
          attr_accessor :widget, :options, :search

          def initialize(options)
            super(**options)
            @widget = 'Dropdown'
            @options = options[:options]
            @search = options[:search] || nil
          end
        end

        class FilePickerField < ActionField
          attr_accessor :widget, :extensions, :max_count, :max_size_mb

          def initialize(options)
            super(**options)
            @widget = 'FilePicker'
            @extensions = options[:extensions] || nil
            @max_size_mb = options[:max_size_mb] || nil
            @max_count = options[:max_count] || nil
          end
        end

        class NumberInputField < ActionField
          attr_accessor :widget, :step, :min, :max

          def initialize(options)
            super(**options)
            @widget = 'NumberInput'
            @step = options[:step] || nil
            @min = options[:min] || nil
            @max = options[:max] || nil
          end
        end

        class JsonEditorField < ActionField
          attr_accessor :widget

          def initialize(options)
            super(**options)
            @widget = 'JsonEditor'
          end
        end

        class NumberInputListField < ActionField
          attr_accessor :widget, :allow_duplicates, :allow_empty_values, :enable_reorder, :min, :max, :step

          def initialize(options)
            super(**options)
            @widget = 'NumberInputList'
            @allow_duplicates = options[:allow_duplicates] || nil
            @allow_empty_values = options[:allow_empty_values] || nil
            @enable_reorder = options[:enable_reorder] || nil
            @min = options[:min] || nil
            @max = options[:max] || nil
            @step = options[:step] || nil
          end
        end

        class RadioGroupField < ActionField
          attr_accessor :widget, :options

          def initialize(options)
            super(**options)
            @widget = 'RadioGroup'
            @options = options[:options]
          end
        end

        class RichTextField < ActionField
          attr_accessor :widget

          def initialize(options)
            super(**options)
            @widget = 'RichText'
          end
        end

        class TextAreaField < ActionField
          attr_accessor :widget, :rows

          def initialize(options)
            super(**options)
            @widget = 'TextArea'
            @rows = options[:rows] || nil
          end
        end

        class TextInputField < ActionField
          attr_accessor :widget

          def initialize(options)
            super(**options)
            @widget = 'TextInput'
          end
        end

        class TextInputListField < ActionField
          attr_accessor :widget, :allow_duplicates, :allow_empty_values, :enable_reorder

          def initialize(options)
            super(**options)
            @widget = 'TextInput'
            @allow_duplicates = options[:allow_duplicates] || nil
            @allow_empty_values = options[:allow_empty_values] || nil
            @enable_reorder = options[:enable_reorder] || nil
          end
        end

        class UserDropdownField < ActionField
          attr_accessor :widget

          def initialize(options)
            super(**options)
            @widget = 'UserDropdown'
          end
        end
      end
    end
  end
end
