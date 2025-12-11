module ForestAdminDatasourceCustomizer
  module Decorators
    module Action
      class BaseAction
        attr_reader :scope, :form, :is_generate_file, :description, :submit_button_label, :execute, :static_form

        def initialize(scope:, form: nil, is_generate_file: false, description: nil, submit_button_label: nil,
                       static_form: false, &execute)
          @scope = scope
          @form = form
          @is_generate_file = is_generate_file
          @description = description
          @submit_button_label = submit_button_label
          @execute = execute
          @static_form = static_form
        end

        def self.from_plain_object(action)
          new(
            scope: action[:scope],
            form: FormFactory.build_elements(action[:form]),
            is_generate_file: action[:is_generate_file],
            description: action[:description],
            submit_button_label: action[:submit_button_label],
            static_form: action[:static_form] || false,
            &action[:execute]
          )
        end

        def build_elements
          @form = FormFactory.build_elements(@form)
          @static_form = @form ? @form&.all?(&:static?) : true

          self
        end

        def validate_fields_ids(form = @form, used = [])
          form&.each do |element|
            if element.type == 'Layout'
              if %w[Page Row].include?(element.component)
                key = element.component == 'Page' ? :elements : :fields
                validate_fields_ids(element.public_send(key), used)
              end
            else
              if used.include?(element.id)
                raise ForestAdminDatasourceToolkit::Exceptions::ForestException,
                      "All field must have different 'id'. Conflict come from field '#{element.id}'"
              end
              used << element.id
            end
          end
        end
      end
    end
  end
end
