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

        # Handle ActiveRecord errors
        if defined?(ActiveRecord) && error.is_a?(ActiveRecord::RecordInvalid)
          return error.record.errors.full_messages.join(', ')
        end

        return error.message if defined?(ActiveRecord) && error.is_a?(ActiveRecord::ActiveRecordError)

        'Unexpected error'
      end

      def get_error_status(error)
        # Return existing status if present
        return error.status if error.respond_to?(:status) && error.status

        # Handle ActiveRecord errors with 400 status
        if defined?(ActiveRecord) && (error.is_a?(ActiveRecord::RecordInvalid) || error.is_a?(ActiveRecord::ActiveRecordError))
          return 400
        end

        # Default to 500 for unexpected errors
        500
      end
    end
  end
end
