module ForestAdminAgent
  module Http
    class Router
      include ForestAdminAgent::Routes

      # Mutex for thread-safe cache operations
      @mutex = Mutex.new

      # Return a frozen, memoized routes hash to avoid expensive recomputation
      #
      # Route computation is expensive because it:
      # - Iterates through all datasource collections and their schemas
      # - Instantiates multiple route handler objects (Actions, Charts, Resources, etc.)
      # - Builds and merges individual route hashes from multiple route handlers
      #
      # Without caching, this computation would run repeatedly, causing significant
      # performance degradation.
      #
      # Caching is ENABLED by default in all environments for optimal performance.
      # To disable caching (not recommended), set `disable_route_cache: true` in config:
      #   ForestAdminAgent::Agent.new options do |builder|
      #     builder.setup(
      #       # ... other options
      #       disable_route_cache: true  # Disables route caching
      #     )
      #   end
      #
      # Thread Safety: Uses Mutex to ensure thread-safe lazy initialization.
      # Multiple threads calling this method concurrently will only compute routes once.
      #
      # @return [Hash] Frozen hash mapping route names to route configurations
      def self.cached_routes
        # Check if caching is disabled via configuration
        if cache_disabled?
          # Return fresh routes on every call (no caching)
          return routes.freeze
        end

        return @cached_routes if @cached_routes

        @mutex.synchronize do
          # Double-check pattern: another thread may have initialized while waiting for lock
          @cached_routes ||= begin
            start_time = Time.now
            computed_routes = routes
            elapsed = ((Time.now - start_time) * 1000).round(2)

            log_message = "[ForestAdmin] Computed #{computed_routes.size} routes " \
                          "in #{elapsed}ms (caching enabled)"
            ForestAdminAgent::Facades::Container.logger.log('Info', log_message)

            computed_routes.freeze
          end
        end
      end

      # Check if route caching is disabled via configuration
      #
      # @return [Boolean] true if caching is disabled, false otherwise (default: false)
      def self.cache_disabled?
        config = ForestAdminAgent::Facades::Container.config_from_cache
        config&.dig(:disable_route_cache) == true
      rescue StandardError
        # If config is not available or an error occurs, default to caching enabled
        false
      end

      # Reset the route cache to force recomputation on next access
      #
      # This is called automatically in development mode by the Rails to_prepare
      # callback to pick up code changes. Should not be called manually unless
      # the datasource structure has been modified at runtime.
      #
      # Thread Safety: Uses Mutex to ensure thread-safe cache invalidation.
      #
      # @return [nil]
      def self.reset_cached_routes!
        @mutex.synchronize do
          @cached_routes = nil
        end
      end

      def self.routes
        route_sources = [
          { name: 'actions', handler: -> { actions_routes } },
          { name: 'api_charts', handler: -> { api_charts_routes } },
          { name: 'health_check', handler: -> { System::HealthCheck.new.routes } },
          { name: 'authentication', handler: -> { Security::Authentication.new.routes } },
          { name: 'scope_invalidation', handler: -> { Security::ScopeInvalidation.new.routes } },
          { name: 'charts', handler: -> { Charts::Charts.new.routes } },
          { name: 'collections', handler: -> { Capabilities::Collections.new.routes } },
          { name: 'native_query', handler: -> { Resources::NativeQuery.new.routes } },
          { name: 'count', handler: -> { Resources::Count.new.routes } },
          { name: 'delete', handler: -> { Resources::Delete.new.routes } },
          { name: 'csv', handler: -> { Resources::Csv.new.routes } },
          { name: 'list', handler: -> { Resources::List.new.routes } },
          { name: 'show', handler: -> { Resources::Show.new.routes } },
          { name: 'store', handler: -> { Resources::Store.new.routes } },
          { name: 'update', handler: -> { Resources::Update.new.routes } },
          { name: 'csv_related', handler: -> { Resources::Related::CsvRelated.new.routes } },
          { name: 'list_related', handler: -> { Resources::Related::ListRelated.new.routes } },
          { name: 'count_related', handler: -> { Resources::Related::CountRelated.new.routes } },
          { name: 'associate_related', handler: -> { Resources::Related::AssociateRelated.new.routes } },
          { name: 'dissociate_related', handler: -> { Resources::Related::DissociateRelated.new.routes } },
          { name: 'update_related', handler: -> { Resources::Related::UpdateRelated.new.routes } },
          { name: 'update_field', handler: -> { Resources::UpdateField.new.routes } }
        ]

        all_routes = {}

        route_sources.each do |source|
          routes = source[:handler].call

          unless routes.is_a?(Hash)
            raise TypeError, "Route handler '#{source[:name]}' returned #{routes.class} instead of Hash"
          end

          all_routes.merge!(routes)
        rescue StandardError => e
          # Provide specific context about which handler failed while preserving exception type
          raise e.class, "Failed to load routes from '#{source[:name]}' handler: #{e.message}"
        end

        all_routes
      end

      def self.actions_routes
        routes = {}
        Facades::Container.datasource.collections.each_value do |collection|
          collection.schema[:actions].each_key do |action_name|
            routes.merge!(Action::Actions.new(collection, action_name).routes)
          end
        end

        routes
      end

      def self.api_charts_routes
        routes = {}
        Facades::Container.datasource.collections.each_value do |collection|
          collection.schema[:charts].each do |chart_name|
            routes.merge!(Charts::ApiChartCollection.new(collection, chart_name).routes)
          end
        end

        Facades::Container.datasource.schema[:charts].each do |chart_name|
          routes.merge!(Charts::ApiChartDatasource.new(chart_name).routes)
        end

        routes
      end
    end
  end
end
