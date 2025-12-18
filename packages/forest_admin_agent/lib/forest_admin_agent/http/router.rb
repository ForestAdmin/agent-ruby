module ForestAdminAgent
  module Http
    class Router
      include ForestAdminAgent::Routes

      # Mutex for thread-safe cache operations
      @mutex = Mutex.new

      def self.cached_routes
        return routes.freeze if cache_disabled?

        return @cached_routes if @cached_routes

        @mutex.synchronize do
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

      def self.cache_disabled?
        config = ForestAdminAgent::Facades::Container.config_from_cache
        config&.dig(:disable_route_cache) == true
      rescue StandardError
        # If config is not available or an error occurs, default to caching enabled
        false
      end

      def self.mcp_server_enabled?
        config = ForestAdminAgent::Facades::Container.config_from_cache
        config&.dig(:enable_mcp_server) == true
      rescue StandardError
        # If config is not available or an error occurs, default to MCP disabled
        false
      end

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

        # Add MCP routes only if enabled via configuration
        if mcp_server_enabled?
          route_sources += [
            { name: 'mcp_oauth_metadata', handler: -> { Mcp::OauthMetadata.new.routes } },
            { name: 'mcp_oauth_authorize', handler: -> { Mcp::OauthAuthorize.new.routes } },
            { name: 'mcp_oauth_token', handler: -> { Mcp::OauthToken.new.routes } },
            { name: 'mcp_endpoint', handler: -> { Mcp::McpEndpoint.new.routes } }
          ]
        end

        all_routes = {}

        route_sources.each do |source|
          routes = source[:handler].call

          unless routes.is_a?(Hash)
            raise TypeError, "Route handler '#{source[:name]}' returned #{routes.class} instead of Hash"
          end

          all_routes.merge!(routes)
        rescue StandardError => e
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
