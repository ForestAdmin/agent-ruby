require 'spec_helper'

module ForestAdminAgent
  module Utils
    module Schema
      include ForestAdminDatasourceToolkit::Components::Actions
      include ForestAdminDatasourceToolkit::Components::Actions::WidgetField

      describe GeneratorActionFieldWidget do
        describe 'build_widget_options' do
          it 'return nil when field has no widget' do
            result = described_class.build_widget_options(
              ActionField.new(type: FieldType::STRING, label: 'Label')
            )

            expect(result).to be_nil
          end

          it 'return nil when the field type is Collection' do
            result = described_class.build_widget_options(
              ActionField.new(type: FieldType::COLLECTION, label: 'Label')
            )

            expect(result).to be_nil
          end

          it 'return nil when the field type is Enum' do
            result = described_class.build_widget_options(
              ActionField.new(type: FieldType::ENUM, label: 'Label', enum_values: %w[value1 value2])
            )

            expect(result).to be_nil
          end

          it 'return nil when the field type is EnumList' do
            result = described_class.build_widget_options(
              ActionField.new(type: FieldType::ENUM_LIST, label: 'Label', enum_values: %w[value1 value2])
            )

            expect(result).to be_nil
          end

          describe 'dropdown' do
            it 'return a valid widget edit' do
              result = described_class.build_widget_options(
                DropdownField.new(
                  type: FieldType::STRING,
                  label: 'Label',
                  options: [
                    { value: 'value1', label: 'Value 1' },
                    { value: 'value2', label: 'Value 2' }
                  ],
                  search: 'static',
                  placeholder: 'Placeholder'
                )
              )

              expect(result).to eq(
                {
                  name: 'dropdown',
                  parameters: {
                    isSearchable: true,
                    searchType: nil,
                    placeholder: 'Placeholder',
                    static: {
                      options: [
                        { value: 'value1', label: 'Value 1' },
                        { value: 'value2', label: 'Value 2' }
                      ]
                    }
                  }
                }
              )
            end

            it 'include the searchType="dynamic"' do
              result = described_class.build_widget_options(
                DropdownField.new(
                  type: FieldType::STRING,
                  label: 'Label',
                  options: %w[1 2],
                  search: 'dynamic',
                  placeholder: 'Placeholder'
                )
              )

              expect(result).to eq(
                {
                  name: 'dropdown',
                  parameters: {
                    isSearchable: true,
                    searchType: 'dynamic',
                    placeholder: 'Placeholder',
                    static: {
                      options: %w[1 2]
                    }
                  }
                }
              )
            end

            it 'return a valid configuration with default values' do
              result = described_class.build_widget_options(DropdownField.new(type: FieldType::STRING, label: 'Label'))

              expect(result).to eq(
                {
                  name: 'dropdown',
                  parameters: {
                    isSearchable: false,
                    searchType: nil,
                    placeholder: nil,
                    static: {
                      options: []
                    }
                  }
                }
              )
            end
          end

          describe 'radioGroup' do
            it 'return a valid widget edit' do
              result = described_class.build_widget_options(
                RadioGroupField.new(
                  type: FieldType::STRING,
                  label: 'Label',
                  options: [
                    { value: 'value1', label: 'Value 1' },
                    { value: 'value2', label: 'Value 2' }
                  ],
                  placeholder: 'Placeholder'
                )
              )

              expect(result).to eq(
                {
                  name: 'radio button',
                  parameters: {
                    static: {
                      options: [
                        { value: 'value1', label: 'Value 1' },
                        { value: 'value2', label: 'Value 2' }
                      ]
                    }
                  }
                }
              )
            end

            it 'return a valid configuration with default values' do
              result = described_class.build_widget_options(RadioGroupField.new(type: FieldType::STRING, label: 'Label'))

              expect(result).to eq(
                {
                  name: 'radio button',
                  parameters: {
                    static: {
                      options: []
                    }
                  }
                }
              )
            end
          end

          describe 'CheckboxGroup' do
            it 'return a valid widget edit' do
              result = described_class.build_widget_options(
                CheckboxGroupField.new(
                  type: FieldType::STRING,
                  label: 'Label',
                  options: [
                    { value: 'value1', label: 'Value 1' },
                    { value: 'value2', label: 'Value 2' }
                  ],
                  placeholder: 'Placeholder'
                )
              )

              expect(result).to eq(
                {
                  name: 'checkboxes',
                  parameters: {
                    static: {
                      options: [
                        { value: 'value1', label: 'Value 1' },
                        { value: 'value2', label: 'Value 2' }
                      ]
                    }
                  }
                }
              )
            end

            it 'return a valid configuration with default values' do
              result = described_class.build_widget_options(
                CheckboxGroupField.new(type: FieldType::STRING, label: 'Label')
              )

              expect(result).to eq(
                {
                  name: 'checkboxes',
                  parameters: {
                    static: {
                      options: []
                    }
                  }
                }
              )
            end
          end

          describe 'Checkbox' do
            it 'return a valid widget edit' do
              result = described_class.build_widget_options(CheckboxField.new(type: FieldType::BOOLEAN, label: 'Label'))

              expect(result).to eq(
                {
                  name: 'boolean editor',
                  parameters: {}
                }
              )
            end

            it 'return a valid configuration with default values' do
              result = described_class.build_widget_options(
                CheckboxGroupField.new(type: FieldType::STRING, label: 'Label')
              )

              expect(result).to eq(
                {
                  name: 'checkboxes',
                  parameters: {
                    static: {
                      options: []
                    }
                  }
                }
              )
            end
          end

          describe 'TextInput' do
            it 'generate a default text input' do
              result = described_class.build_widget_options(TextInputField.new(type: FieldType::STRING, label: 'Label'))

              expect(result).to eq(
                {
                  name: 'text editor',
                  parameters: {
                    placeholder: nil
                  }
                }
              )
            end

            it 'add the placeholder if present' do
              result = described_class.build_widget_options(
                TextInputField.new(type: FieldType::STRING, label: 'Label', placeholder: 'Placeholder')
              )

              expect(result).to eq(
                {
                  name: 'text editor',
                  parameters: {
                    placeholder: 'Placeholder'
                  }
                }
              )
            end
          end

          describe 'TextInputList' do
            it 'return a valid widget edit with default values' do
              result = described_class.build_widget_options(
                TextInputListField.new(type: FieldType::STRING_LIST, label: 'Label')
              )

              expect(result).to eq(
                {
                  name: 'input array',
                  parameters: {
                    placeholder: nil,
                    allowDuplicate: false,
                    allowEmptyValue: false,
                    enableReorder: true
                  }
                }
              )
            end

            it 'pass the options to the widget' do
              result = described_class.build_widget_options(
                TextInputListField.new(
                  type: FieldType::STRING_LIST,
                  label: 'Label',
                  placeholder: 'Placeholder',
                  allow_duplicates: true,
                  allow_empty_values: true,
                  enable_reorder: false
                )
              )

              expect(result).to eq(
                {
                  name: 'input array',
                  parameters: {
                    placeholder: 'Placeholder',
                    allowDuplicate: true,
                    allowEmptyValue: true,
                    enableReorder: false
                  }
                }
              )
            end
          end

          describe 'TextArea' do
            it 'return a valid widget edit with default values' do
              result = described_class.build_widget_options(
                TextAreaField.new(type: FieldType::STRING_LIST, label: 'Label')
              )

              expect(result).to eq(
                {
                  name: 'text area editor',
                  parameters: {
                    placeholder: nil,
                    rows: nil
                  }
                }
              )
            end

            it 'pass the options to the widget' do
              result = described_class.build_widget_options(
                TextAreaField.new(
                  type: FieldType::STRING_LIST,
                  label: 'Label',
                  placeholder: 'Placeholder',
                  rows: 10
                )
              )

              expect(result).to eq(
                {
                  name: 'text area editor',
                  parameters: {
                    placeholder: 'Placeholder',
                    rows: 10
                  }
                }
              )
            end
          end

          describe 'RichText' do
            it 'return a valid widget edit with default values' do
              result = described_class.build_widget_options(
                RichTextField.new(type: FieldType::STRING_LIST, label: 'Label')
              )

              expect(result).to eq(
                {
                  name: 'rich text',
                  parameters: {
                    placeholder: nil
                  }
                }
              )
            end

            it 'pass the options to the widget' do
              result = described_class.build_widget_options(
                RichTextField.new(type: FieldType::STRING_LIST, label: 'Label', placeholder: 'Placeholder')
              )

              expect(result).to eq(
                {
                  name: 'rich text',
                  parameters: {
                    placeholder: 'Placeholder'
                  }
                }
              )
            end
          end

          describe 'NumberInput' do
            it 'return a valid widget edit with default values' do
              result = described_class.build_widget_options(
                NumberInputField.new(type: FieldType::STRING_LIST, label: 'Label')
              )

              expect(result).to eq(
                {
                  name: 'number input',
                  parameters: {
                    placeholder: nil,
                    min: nil,
                    max: nil,
                    step: nil
                  }
                }
              )
            end

            it 'pass the options to the widget' do
              result = described_class.build_widget_options(
                NumberInputField.new(
                  type: FieldType::STRING_LIST,
                  label: 'Label',
                  placeholder: 'Placeholder',
                  min: 10,
                  max: 100,
                  step: 2
                )
              )

              expect(result).to eq(
                {
                  name: 'number input',
                  parameters: {
                    placeholder: 'Placeholder',
                    min: 10,
                    max: 100,
                    step: 2
                  }
                }
              )
            end
          end

          describe 'NumberInputList' do
            it 'return a valid widget edit with default values' do
              result = described_class.build_widget_options(
                NumberInputListField.new(type: FieldType::STRING_LIST, label: 'Label')
              )

              expect(result).to eq(
                {
                  name: 'input array',
                  parameters: {
                    placeholder: nil,
                    allowDuplicate: false,
                    enableReorder: true,
                    min: nil,
                    max: nil,
                    step: nil
                  }
                }
              )
            end

            it 'pass the options to the widget' do
              result = described_class.build_widget_options(
                NumberInputListField.new(
                  type: FieldType::STRING_LIST,
                  label: 'Label',
                  placeholder: 'Placeholder',
                  allow_duplicates: true,
                  enable_reorder: false,
                  min: 10,
                  max: 100,
                  step: 2
                )
              )

              expect(result).to eq(
                {
                  name: 'input array',
                  parameters: {
                    placeholder: 'Placeholder',
                    allowDuplicate: true,
                    enableReorder: false,
                    min: 10,
                    max: 100,
                    step: 2
                  }
                }
              )
            end
          end

          describe 'ColorPicker' do
            it 'return a valid widget edit with default values' do
              result = described_class.build_widget_options(
                ColorPickerField.new(type: FieldType::STRING_LIST, label: 'Label')
              )

              expect(result).to eq(
                {
                  name: 'color editor',
                  parameters: {
                    enableOpacity: false,
                    placeholder: nil,
                    quickPalette: nil
                  }
                }
              )
            end
          end

          describe 'Currency' do
            it 'return a valid widget edit with default values' do
              result = described_class.build_widget_options(
                CurrencyInputField.new(type: FieldType::NUMBER, label: 'Label', currency: 'EUR')
              )

              expect(result).to eq(
                {
                  name: 'price editor',
                  parameters: {
                    placeholder: nil,
                    min: nil,
                    max: nil,
                    step: nil,
                    currency: 'EUR',
                    base: 'Unit'
                  }
                }
              )
            end

            it 'pass the options to the widget' do
              result = described_class.build_widget_options(
                CurrencyInputField.new(
                  type: FieldType::NUMBER,
                  label: 'Label',
                  currency: 'USD',
                  min: 10,
                  max: 100,
                  step: 2,
                  base: 'Cents'
                )
              )

              expect(result).to eq(
                {
                  name: 'price editor',
                  parameters: {
                    placeholder: nil,
                    currency: 'USD',
                    min: 10,
                    max: 100,
                    step: 2,
                    base: 'Cent'
                  }
                }
              )
            end
          end

          describe 'DatePicker' do
            it 'return a valid widget edit with default values' do
              result = described_class.build_widget_options(
                DatePickerField.new(type: FieldType::DATE, label: 'Label')
              )

              expect(result).to eq(
                {
                  name: 'date editor',
                  parameters: {
                    placeholder: nil,
                    format: nil,
                    minDate: nil,
                    maxDate: nil
                  }
                }
              )
            end

            it 'pass the options to the widget' do
              result = described_class.build_widget_options(
                DatePickerField.new(
                  type: FieldType::DATE,
                  label: 'Label',
                  min: Date.new(2000, 2, 1),
                  max: Date.new(2024, 2, 1)
                )
              )

              expect(result).to eq(
                {
                  name: 'date editor',
                  parameters: {
                    placeholder: nil,
                    format: nil,
                    minDate: '2000-02-01',
                    maxDate: '2024-02-01'
                  }
                }
              )
            end
          end

          describe 'TimePicker' do
            it 'return a valid widget edit with default values' do
              result = described_class.build_widget_options(
                TimePickerField.new(type: FieldType::TIME, label: 'Label')
              )

              expect(result).to eq(
                {
                  name: 'time editor',
                  parameters: {}
                }
              )
            end
          end

          describe 'JsonEditor' do
            it 'return a valid widget edit with default values' do
              result = described_class.build_widget_options(
                JsonEditorField.new(type: FieldType::JSON, label: 'Label')
              )

              expect(result).to eq(
                {
                  name: 'json code editor',
                  parameters: {}
                }
              )
            end
          end

          describe 'UserDropdown' do
            it 'generate a default text input' do
              result = described_class.build_widget_options(UserDropdownField.new(type: FieldType::STRING, label: 'Label'))

              expect(result).to eq(
                {
                  name: 'assignee editor',
                  parameters: {
                    placeholder: nil
                  }
                }
              )
            end

            it 'add the placeholder if present' do
              result = described_class.build_widget_options(
                UserDropdownField.new(type: FieldType::STRING, label: 'Label', placeholder: 'Placeholder')
              )

              expect(result).to eq(
                {
                  name: 'assignee editor',
                  parameters: {
                    placeholder: 'Placeholder'
                  }
                }
              )
            end
          end

          describe 'AddressAutocomplete' do
            it 'generate a default text input' do
              result = described_class.build_widget_options(
                AddressAutocompleteField.new(type: FieldType::STRING, label: 'Label')
              )

              expect(result).to eq(
                {
                  name: 'address editor',
                  parameters: {
                    placeholder: nil
                  }
                }
              )
            end

            it 'add the placeholder if present' do
              result = described_class.build_widget_options(
                AddressAutocompleteField.new(type: FieldType::STRING, label: 'Label', placeholder: 'Placeholder')
              )

              expect(result).to eq(
                {
                  name: 'address editor',
                  parameters: {
                    placeholder: 'Placeholder'
                  }
                }
              )
            end
          end

          describe 'FilePicker' do
            it 'generate a default file input' do
              result = described_class.build_widget_options(
                FilePickerField.new(type: FieldType::FILE, label: 'Label')
              )

              expect(result).to eq(
                {
                  name: 'file picker',
                  parameters: {
                    prefix: nil,
                    filesExtensions: nil,
                    filesSizeLimit: nil,
                    filesCountLimit: nil
                  }
                }
              )
            end

            it 'add the options if present' do
              result = described_class.build_widget_options(
                FilePickerField.new(
                  type: FieldType::FILE,
                  label: 'Label',
                  extensions: ['png', 'jpg'],
                  max_count: 10,
                  max_size_mb: 12
                )
              )

              expect(result).to eq(
                {
                  name: 'file picker',
                  parameters: {
                    prefix: nil,
                    filesExtensions: %w[png jpg],
                    filesSizeLimit: 12,
                    filesCountLimit: 10
                  }
                }
              )
            end
          end
        end
      end
    end
  end
end
