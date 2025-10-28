module ForestAdminDatasourceCustomizer
  module Decorators
    module Hook
      module Context
        class HookContext < ForestAdminDatasourceCustomizer::Context::CollectionCustomizationContext
          include ForestAdminAgent::Http::Exceptions
          def raise_validation_error(message)
            raise ValidationError, message
          end

          def raise_forbidden_error(message)
            raise ForbiddenError, message
          end

          def raise_error(message)
            raise UnprocessableError, message
          end
        end
      end
    end
  end
end
