require 'spec_helper'

module ForestAdminAgent
  module Utils
    module Schema
      include ForestAdminDatasourceToolkit::Components::Actions
      include ForestAdminDatasourceToolkit::Components::Actions::WidgetField

      describe ActionFields do
        subject(:action_fields) { described_class }

        describe 'collection_field?' do
          it 'return true when the field type is Collection' do
            result = action_fields.collection_field?(
              ActionField.new(type: FieldType::COLLECTION, label: 'Label')
            )

            expect(result).to be_truthy
          end

          FieldType.all.reject { |type| type == FieldType::COLLECTION }.each do |type|
            it "return false when the field type is '#{type}'" do
              result = action_fields.collection_field?(
                ActionField.new(type: type, label: 'Label')
              )

              expect(result).to be_falsey
            end
          end
        end

        describe 'enum_field?' do
          it 'return true when the field type is enum' do
            result = action_fields.enum_field?(
              ActionField.new(type: FieldType::ENUM, label: 'Label')
            )

            expect(result).to be_truthy
          end

          FieldType.all.reject { |type| type == FieldType::ENUM }.each do |type|
            it "return false when the field type is '#{type}'" do
              result = action_fields.enum_field?(
                ActionField.new(type: type, label: 'Label')
              )

              expect(result).to be_falsey
            end
          end
        end

        describe 'enum_list_field?' do
          it 'return true when the field type is enum list' do
            result = action_fields.enum_list_field?(
              ActionField.new(type: FieldType::ENUM_LIST, label: 'Label')
            )

            expect(result).to be_truthy
          end

          FieldType.all.reject { |type| type == FieldType::ENUM_LIST }.each do |type|
            it "return false when the field type is '#{type}'" do
              result = action_fields.enum_list_field?(
                ActionField.new(type: type, label: 'Label')
              )

              expect(result).to be_falsey
            end
          end
        end

        describe 'file_field?' do
          it 'return true when the field type is file' do
            result = action_fields.file_field?(
              ActionField.new(type: FieldType::FILE, label: 'Label')
            )

            expect(result).to be_truthy
          end

          FieldType.all.reject { |type| type == FieldType::FILE }.each do |type|
            it "return false when the field type is '#{type}'" do
              result = action_fields.file_field?(
                ActionField.new(type: type, label: 'Label')
              )

              expect(result).to be_falsey
            end
          end
        end

        describe 'file_list_field?' do
          it 'return true when the field type is file list' do
            result = action_fields.file_list_field?(
              ActionField.new(type: FieldType::FILE_LIST, label: 'Label')
            )

            expect(result).to be_truthy
          end

          FieldType.all.reject { |type| type == FieldType::FILE_LIST }.each do |type|
            it "return false when the field type is '#{type}'" do
              result = action_fields.file_list_field?(
                ActionField.new(type: type, label: 'Label')
              )

              expect(result).to be_falsey
            end
          end
        end

        describe 'dropdown_field?' do
          it 'return true when the field type is Dropdown' do
            result = action_fields.dropdown_field?(
              DropdownField.new(type: FieldType::STRING, label: 'Label')
            )

            expect(result).to be(true)
          end

          it 'return false when the field type is not Dropdown' do
            result = action_fields.dropdown_field?(
              ActionField.new(type: FieldType::STRING, label: 'Label')
            )

            expect(result).to be(false)
          end
        end

        describe 'radio_group_field?' do
          it 'return true when the field type is radio group' do
            result = action_fields.radio_group_field?(
              RadioGroupField.new(type: FieldType::STRING, label: 'Label')
            )

            expect(result).to be(true)
          end

          it 'return false when the field type is not radio group' do
            result = action_fields.radio_group_field?(
              ActionField.new(type: FieldType::STRING, label: 'Label')
            )

            expect(result).to be(false)
          end
        end

        describe 'checkbox_group_field?' do
          it 'return true when the field type is checkbox group' do
            result = action_fields.checkbox_group_field?(
              CheckboxGroupField.new(type: FieldType::STRING, label: 'Label')
            )

            expect(result).to be(true)
          end

          it 'return false when the field type is not checkbox group' do
            result = action_fields.checkbox_group_field?(
              ActionField.new(type: FieldType::STRING, label: 'Label')
            )

            expect(result).to be(false)
          end
        end

        describe 'checkbox_field?' do
          it 'return true when the field type is checkbox' do
            result = action_fields.checkbox_field?(
              CheckboxField.new(type: FieldType::STRING, label: 'Label')
            )

            expect(result).to be(true)
          end

          it 'return false when the field type is not checkbox' do
            result = action_fields.checkbox_field?(
              ActionField.new(type: FieldType::STRING, label: 'Label')
            )

            expect(result).to be(false)
          end
        end

        describe 'text_input_field?' do
          it 'return true when the field type is text input' do
            result = action_fields.text_input_field?(
              TextInputField.new(type: FieldType::STRING, label: 'Label')
            )

            expect(result).to be(true)
          end

          it 'return false when the field type is not text input' do
            result = action_fields.text_input_field?(
              ActionField.new(type: FieldType::STRING, label: 'Label')
            )

            expect(result).to be(false)
          end
        end

        describe 'text_input_list_field?' do
          it 'return true when the field type is text input list' do
            result = action_fields.text_input_list_field?(
              TextInputListField.new(type: FieldType::STRING_LIST, label: 'Label')
            )

            expect(result).to be(true)
          end

          it 'return false when the field type is not text input' do
            result = action_fields.text_input_list_field?(
              ActionField.new(type: FieldType::STRING, label: 'Label')
            )

            expect(result).to be(false)
          end
        end

        describe 'text_area_field?' do
          it 'return true when the field type is text area' do
            result = action_fields.text_area_field?(
              TextAreaField.new(type: FieldType::STRING, label: 'Label')
            )

            expect(result).to be(true)
          end

          it 'return false when the field type is not text area' do
            result = action_fields.text_area_field?(
              ActionField.new(type: FieldType::STRING, label: 'Label')
            )

            expect(result).to be(false)
          end
        end

        describe 'rich_text_field?' do
          it 'return true when the field type is rich text' do
            result = action_fields.rich_text_field?(
              RichTextField.new(type: FieldType::STRING, label: 'Label')
            )

            expect(result).to be(true)
          end

          it 'return false when the field type is not rich text' do
            result = action_fields.rich_text_field?(
              ActionField.new(type: FieldType::STRING, label: 'Label')
            )

            expect(result).to be(false)
          end
        end

        describe 'number_input_field?' do
          it 'return true when the field type is number input' do
            result = action_fields.number_input_field?(
              NumberInputField.new(type: FieldType::NUMBER, label: 'Label')
            )

            expect(result).to be(true)
          end

          it 'return false when the field type is not number input' do
            result = action_fields.number_input_field?(
              ActionField.new(type: FieldType::NUMBER, label: 'Label')
            )

            expect(result).to be(false)
          end
        end

        describe 'number_input_list_field?' do
          it 'return true when the field type is number input list' do
            result = action_fields.number_input_list_field?(
              NumberInputListField.new(type: FieldType::NUMBER_LIST, label: 'Label')
            )

            expect(result).to be(true)
          end

          it 'return false when the field type is not number input list' do
            result = action_fields.number_input_list_field?(
              ActionField.new(type: FieldType::NUMBER, label: 'Label')
            )

            expect(result).to be(false)
          end
        end

        describe 'color_picker_field?' do
          it 'return true when the field type is color picker' do
            result = action_fields.color_picker_field?(
              ColorPickerField.new(type: FieldType::STRING, label: 'Label')
            )

            expect(result).to be(true)
          end

          it 'return false when the field type is not color picker' do
            result = action_fields.color_picker_field?(
              ActionField.new(type: FieldType::NUMBER, label: 'Label')
            )

            expect(result).to be(false)
          end
        end

        describe 'currency_input_field?' do
          it 'return true when the field type is currency input field' do
            result = action_fields.currency_input_field?(
              CurrencyInputField.new(type: FieldType::NUMBER, label: 'Label')
            )

            expect(result).to be(true)
          end

          it 'return false when the field type is not currency input field' do
            result = action_fields.currency_input_field?(
              ActionField.new(type: FieldType::NUMBER, label: 'Label')
            )

            expect(result).to be(false)
          end
        end

        describe 'json_editor_field?' do
          it 'return true when the field type is json editor' do
            result = action_fields.json_editor_field?(
              JsonEditorField.new(type: FieldType::STRING, label: 'Label')
            )

            expect(result).to be(true)
          end

          it 'return false when the field type is not json editor' do
            result = action_fields.json_editor_field?(
              ActionField.new(type: FieldType::NUMBER, label: 'Label')
            )

            expect(result).to be(false)
          end
        end

        describe 'user_dropdown_field?' do
          it 'return true when the field type is user dropdown' do
            result = action_fields.user_dropdown_field?(
              UserDropdownField.new(type: FieldType::STRING, label: 'Label')
            )

            expect(result).to be(true)
          end

          it 'return false when the field type is not user dropdown' do
            result = action_fields.user_dropdown_field?(
              ActionField.new(type: FieldType::NUMBER, label: 'Label')
            )

            expect(result).to be(false)
          end
        end

        describe 'address_autocomplete_field?' do
          it 'return true when the field type is address autocomplete' do
            result = action_fields.address_autocomplete_field?(
              AddressAutocompleteField.new(type: FieldType::STRING, label: 'Label')
            )

            expect(result).to be(true)
          end

          it 'return false when the field type is not address autocomplete' do
            result = action_fields.address_autocomplete_field?(
              ActionField.new(type: FieldType::NUMBER, label: 'Label')
            )

            expect(result).to be(false)
          end
        end

        describe 'file_picker_field?' do
          it 'return true when the field type is file picker' do
            result = action_fields.file_picker_field?(
              FilePickerField.new(type: FieldType::STRING, label: 'Label')
            )

            expect(result).to be(true)
          end

          it 'return false when the field type is not file picker' do
            result = action_fields.file_picker_field?(
              ActionField.new(type: FieldType::NUMBER, label: 'Label')
            )

            expect(result).to be(false)
          end
        end

        describe 'widget?' do
          it 'return true when the field is a widget' do
            result = action_fields.widget?(
              FilePickerField.new(type: FieldType::STRING, label: 'Label')
            )

            expect(result).to be(true)
          end

          it 'return false when the field is not a widget' do
            result = action_fields.widget?(
              ActionField.new(type: FieldType::NUMBER, label: 'Label')
            )

            expect(result).to be(false)
          end
        end
      end
    end
  end
end
