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

        'Unexpected error'
      end
    end
  end
end
