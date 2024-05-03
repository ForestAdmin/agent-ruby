module ForestAdminAgent
  module Http
    module ErrorHandling
      def get_error_message(error)
        return error.message if error.ancestors.include? ForestAdminAgent::Http::Exceptions::HttpException

        if (customizer = ForestAdminAgent::Facades::Container.cache(:customize_error_message))
          message = customizer.call(error)
          return message if message
        end

        'Unexpected error'
      end
    end
  end
end
