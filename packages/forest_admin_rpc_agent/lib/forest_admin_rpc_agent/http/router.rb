module ForestAdminRpcAgent
  module Http
    class Router
      # Mutex for thread-safe cache operations
      @mutex = Mutex.new

      def self.cached_route_instances
        return route_instances.freeze if cache_disabled?

        return @cached_route_instances if @cached_route_instances

        @mutex.synchronize do
          @cached_route_instances ||= begin
            start_time = Time.now
            computed_routes = route_instances
            elapsed = ((Time.now - start_time) * 1000).round(2)

            log_message = "[ForestAdminRpcAgent] Computed #{computed_routes.size} routes " \
                          "in #{elapsed}ms (caching enabled)"
            log_to_available_logger('Info', log_message)

            computed_routes.freeze
          end
        end
      end

      def self.cache_disabled?
        config = ForestAdminRpcAgent::Facades::Container.config_from_cache
        config&.dig(:disable_route_cache) == true
      rescue StandardError
        # Config not available, default to caching enabled
        false
      end

      def self.reset_cached_route_instances!
        @mutex.synchronize do
          @cached_route_instances = nil
        end
      end

      def self.log_to_available_logger(level, message)
        ForestAdminRpcAgent::Facades::Container.logger.log(level, message)
      rescue StandardError
        puts message
      end

      def self.route_instances
        route_classes = ForestAdminRpcAgent::Routes.constants.reject { |route| route.to_s == 'BaseRoute' }

        route_instances = []

        route_classes.each do |route_name|
          route_class = ForestAdminRpcAgent::Routes.const_get(route_name)

          begin
            route_instance = route_class.new

            unless route_instance.respond_to?(:registered)
              log_to_available_logger(
                'Warn',
                "Skipping route: #{route_class} (does not respond to :registered)"
              )
              next
            end

            route_instances << route_instance
          rescue StandardError => e
            raise e.class, "Failed to instantiate route '#{route_name}': #{e.message}"
          end
        end

        route_instances
      end
    end
  end
end
