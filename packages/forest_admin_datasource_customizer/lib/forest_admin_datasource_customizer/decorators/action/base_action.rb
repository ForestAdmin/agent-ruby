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
          return form&.all?(&:static?) && form&.none? { |field| field.type == 'Layout' } if form

          true
        end
      end
    end
  end
end
