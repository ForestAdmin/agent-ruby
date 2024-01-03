module ForestAdminDatasourceCustomizer
  module Decorators
    module Actions
      class BaseAction
        attr_reader :scope, :form, :is_generate_file, :execute

        def initialize(scope:, form: [], is_generate_file: false)
          @scope = scope
          @form = form
          @is_generate_file = is_generate_file
          @execute = yield
        end

        def static_form?
          form.all?(&:static?)
        end
      end
    end
  end
end
