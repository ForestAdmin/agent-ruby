module ForestAdminDatasourceCustomizer
  module Decorators
    module Action
      class BaseAction
        attr_reader :scope, :form, :is_generate_file, :description, :submit_button_label, :execute

        def initialize(scope:, form: nil, is_generate_file: false, description: nil, submit_button_label: nil, &execute)
          @scope = scope
          @form = form
          @is_generate_file = is_generate_file
          @description = description
          @submit_button_label = submit_button_label
          @execute = execute
        end

        def build_elements
          @form = FormFactory.build_elements(form)
        end

        def static_form?
          return form&.all?(&:static?) if form

          true
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
