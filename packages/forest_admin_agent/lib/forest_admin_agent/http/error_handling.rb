module ForestAdminAgent
  module Http
    module ErrorHandling
      def get_error_message(error)
        if error.class.respond_to?(:ancestors) && error.class.ancestors.include?(ForestAdminAgent::Http::Exceptions::HttpException)
          return error.message
        end

        if (customizer = ForestAdminAgent::Facades::Container.cache(:customize_error_message))
          message = eval(customizer).call(error)
          return message if message
        end

        return error.message if error.is_a?(ForestAdminDatasourceToolkit::Exceptions::ValidationError)

        'Unexpected error'
      end

      def get_error_status(error)
        # Return existing status if present
        return error.status if error.respond_to?(:status) && error.status

        # Handle ActiveRecord errors with 400 status
        return 400 if error.is_a?(ForestAdminDatasourceToolkit::Exceptions::ValidationError)

        # Default to 500 for unexpected errors
        500
      end
    end
  end
end
