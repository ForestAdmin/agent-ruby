module ForestAdminAgent
  module Utils
    module Schema
      class GeneratorActionFieldWidget
        include ForestAdminAgent::Http::Exceptions

        def self.build_widget_options(field)
          return if !ActionFields.widget?(field) || %w[Collection Enum EnumList].include?(field.type)

          return build_dropdown_widget_edit(field) if ActionFields.dropdown_field?(field)

          return build_radio_group_widget_edit(field) if ActionFields.radio_group_field?(field)

          return build_checkbox_group_widget_edit(field) if ActionFields.checkbox_group_field?(field)

          return build_checkbox_widget_edit(field) if ActionFields.checkbox_field?(field)

          return build_text_input_widget_edit(field) if ActionFields.text_input_field?(field)

          return build_date_picker_widget_edit(field) if ActionFields.date_picker_field?(field)

          return build_text_input_list_widget_edit(field) if ActionFields.text_input_list_field?(field)

          return build_text_area_widget_edit(field) if ActionFields.text_area_field?(field)

          return build_rich_text_widget_edit(field) if ActionFields.rich_text_field?(field)

          return build_number_input_widget_edit(field) if ActionFields.number_input_field?(field)

          return build_color_picker_widget_edit(field) if ActionFields.color_picker_field?(field)

          return build_number_input_list_widget_edit(field) if ActionFields.number_input_list_field?(field)

          return build_currency_input_widget_edit(field) if ActionFields.currency_input_field?(field)

          return build_user_dropdown_widget_edit(field) if ActionFields.user_dropdown_field?(field)

          return build_time_picker_widget_edit(field) if ActionFields.time_picker_field?(field)

          return build_json_editor_widget_edit(field) if ActionFields.json_editor_field?(field)

          return build_file_picker_widget_edit(field) if ActionFields.file_picker_field?(field)

          return build_address_autocomplete_widget_edit(field) if ActionFields.address_autocomplete_field?(field)

          raise InternalServerError.new(
            "Unsupported widget type: #{field&.widget}",
            details: { widget: field&.widget, field_type: field&.type }
          )
        end

        class << self
          private

          def build_dropdown_widget_edit(field)
            {
              name: 'dropdown',
              parameters: {
                searchType: field.search == 'dynamic' ? 'dynamic' : nil,
                isSearchable: %w[static dynamic].include?(field.search),
                placeholder: field.placeholder,
                static: { options: field.options || [] }
              }
            }
          end

          def build_radio_group_widget_edit(field)
            {
              name: 'radio button',
              parameters: {
                static: {
                  options: field.options || []
                }
              }
            }
          end

          def build_checkbox_group_widget_edit(field)
            {
              name: 'checkboxes',
              parameters: {
                static: {
                  options: field.options || []
                }
              }
            }
          end

          def build_checkbox_widget_edit(_field)
            {
              name: 'boolean editor',
              parameters: {}
            }
          end

          def build_text_input_widget_edit(field)
            {
              name: 'text editor',
              parameters: {
                placeholder: field.placeholder
              }
            }
          end

          def build_date_picker_widget_edit(field)
            {
              name: 'date editor',
              parameters: {
                format: field.format,
                placeholder: field.placeholder,
                minDate: field.min.is_a?(Date) ? field.min.iso8601 : nil,
                maxDate: field.max.is_a?(Date) ? field.max.iso8601 : nil
              }
            }
          end

          def build_text_input_list_widget_edit(field)
            {
              name: 'input array',
              parameters: {
                placeholder: field.placeholder,
                allowDuplicate: field.allow_duplicates,
                allowEmptyValue: field.allow_empty_values,
                enableReorder: field.enable_reorder
              }
            }
          end

          def build_text_area_widget_edit(field)
            {
              name: 'text area editor',
              parameters: {
                placeholder: field.placeholder,
                rows: valid_number?(field.rows) && field.rows.positive? ? field.rows.round : nil
              }
            }
          end

          def build_rich_text_widget_edit(field)
            {
              name: 'rich text',
              parameters: {
                placeholder: field.placeholder
              }
            }
          end

          def build_number_input_widget_edit(field)
            {
              name: 'number input',
              parameters: {
                placeholder: field.placeholder,
                min: valid_number?(field.min) ? field.min : nil,
                max: valid_number?(field.max) ? field.max : nil,
                step: valid_number?(field.step) ? field.step : nil
              }
            }
          end

          def build_color_picker_widget_edit(field)
            {
              name: 'color editor',
              parameters: {
                placeholder: field.placeholder,
                enableOpacity: field.enable_opacity,
                quickPalette: field.quick_palette
              }
            }
          end

          def build_number_input_list_widget_edit(field)
            {
              name: 'input array',
              parameters: {
                placeholder: field.placeholder,
                allowDuplicate: field.allow_duplicates.nil? ? false : field.allow_duplicates,
                enableReorder: field.enable_reorder.nil? || field.enable_reorder,
                min: valid_number?(field.min) ? field.min : nil,
                max: valid_number?(field.max) ? field.max : nil,
                step: valid_number?(field.step) ? field.step : nil
              }
            }
          end

          def build_currency_input_widget_edit(field)
            {
              name: 'price editor',
              parameters: {
                placeholder: field.placeholder,
                min: valid_number?(field.min) ? field.min : nil,
                max: valid_number?(field.max) ? field.max : nil,
                step: valid_number?(field.step) ? field.step : nil,
                currency: field.currency.is_a?(String) && field.currency.length == 3 ? field.currency.upcase : nil,
                base: map_currency_base(field.base)
              }
            }
          end

          def build_time_picker_widget_edit(_field)
            {
              name: 'time editor',
              parameters: {}
            }
          end

          def build_json_editor_widget_edit(_field)
            {
              name: 'json code editor',
              parameters: {}
            }
          end

          def build_file_picker_widget_edit(field)
            {
              name: 'file picker',
              parameters: {
                prefix: nil,
                filesExtensions: field.extensions,
                filesSizeLimit: field.max_size_mb,
                filesCountLimit: field.max_count
              }
            }
          end

          def build_address_autocomplete_widget_edit(field)
            {
              name: 'address editor',
              parameters: {
                placeholder: field.placeholder
              }
            }
          end

          def build_user_dropdown_widget_edit(field)
            {
              name: 'assignee editor',
              parameters: {
                placeholder: field.placeholder
              }
            }
          end

          def valid_number?(value)
            if value.is_a? String
              begin
                return true if value.to_f
              rescue StandardError
                false
              end
            end

            value.is_a? Numeric
          end

          def map_currency_base(base)
            return 'Cent' if %w[cents cent].include?(base.downcase)

            'Unit'
          end
        end
      end
    end
  end
end
