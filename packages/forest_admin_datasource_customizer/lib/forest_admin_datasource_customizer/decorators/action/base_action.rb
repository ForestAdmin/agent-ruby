module ForestAdminDatasourceCustomizer
  module Decorators
    module Action
      class BaseAction
        attr_reader :scope, :form, :is_generate_file, :execute

        def initialize(scope:, form: nil, is_generate_file: false, &execute)
          @scope = scope
          @form = form
          @is_generate_file = is_generate_file
          @execute = execute
        end

        def build_fields
          @form = @form&.map do |field|
            DynamicField.new(**field)
          end
        end

        def static_form?
          return form&.all?(&:static?) if form

          true
        end
      end
    end
  end
end
