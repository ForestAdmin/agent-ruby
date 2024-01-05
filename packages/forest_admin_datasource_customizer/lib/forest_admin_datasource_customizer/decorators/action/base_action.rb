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

        def static_form?
          form&.all?(&:static?)
        end
      end
    end
  end
end
