require 'spec_helper'

module ForestAdminAgent
  module Http
    describe Router do
      describe '.cached_routes' do
        before do
          described_class.reset_cached_routes!
        end

        after do
          described_class.reset_cached_routes!
        end

        it 'returns a hash of routes' do
          routes = described_class.cached_routes
          expect(routes).to be_a(Hash)
        end

        it 'returns a frozen hash' do
          routes = described_class.cached_routes
          expect(routes).to be_frozen
        end

        it 'memoizes the routes on subsequent calls' do
          first_call = described_class.cached_routes
          first_object_id = first_call.object_id

          # Second call should return the same object (memoized)
          second_call = described_class.cached_routes
          second_object_id = second_call.object_id

          expect(second_object_id).to eq(first_object_id)
        end

        it 'does not recompute routes on subsequent calls' do
          allow(described_class).to receive(:routes).and_call_original

          described_class.cached_routes

          described_class.cached_routes

          # routes should only be called once (for the first call)
          expect(described_class).to have_received(:routes).once
        end

        it 'includes standard routes from route handlers' do
          routes = described_class.cached_routes
          route_names = routes.keys.map(&:to_s)

          expect(route_names).to include('forest')
          expect(route_names).to include('forest_authentication')
        end
      end

      describe '.reset_cached_routes!' do
        before do
          described_class.reset_cached_routes!
        end

        it 'clears the cached routes' do
          first_routes = described_class.cached_routes
          first_object_id = first_routes.object_id

          described_class.reset_cached_routes!

          # Get routes again - should be a new object
          second_routes = described_class.cached_routes
          second_object_id = second_routes.object_id

          expect(second_object_id).not_to eq(first_object_id)
        end

        it 'allows routes to be recomputed after reset' do
          described_class.cached_routes

          described_class.reset_cached_routes!

          allow(described_class).to receive(:routes).and_call_original

          # Calling cached_routes should trigger routes computation again
          described_class.cached_routes

          expect(described_class).to have_received(:routes).once
        end

        it 'returns nil' do
          described_class.cached_routes
          result = described_class.reset_cached_routes!
          expect(result).to be_nil
        end
      end

      describe '.routes' do
        it 'returns a hash' do
          routes = described_class.routes
          expect(routes).to be_a(Hash)
        end

        it 'includes routes from all route handlers' do
          routes = described_class.routes

          expect(routes).not_to be_empty

          routes.each do |name, route_config|
            expect(name).to be_a(String).or be_a(Symbol)
            expect(route_config).to be_a(Hash)
            expect(route_config).to have_key(:uri)
            expect(route_config).to have_key(:method)
          end
        end

        it 'merges routes from actions_routes' do
          actions_routes = described_class.actions_routes
          all_routes = described_class.routes

          actions_routes.each_key do |action_route_name|
            expect(all_routes).to have_key(action_route_name)
          end
        end

        it 'merges routes from api_charts_routes' do
          api_charts_routes = described_class.api_charts_routes
          all_routes = described_class.routes

          api_charts_routes.each_key do |chart_route_name|
            expect(all_routes).to have_key(chart_route_name)
          end
        end

        context 'when route handler fails' do
          it 'raises descriptive error when a route handler fails to instantiate' do
            allow(ForestAdminAgent::Routes::Security::Authentication).to receive(:new)
              .and_raise(StandardError, 'Database connection failed')

            expect do
              described_class.routes
            end.to raise_error(StandardError, /Failed to load routes from 'authentication' handler: Database connection failed/)
          end

          it 'preserves original exception type in error message' do
            allow(ForestAdminAgent::Routes::System::HealthCheck).to receive(:new)
              .and_raise(ArgumentError, 'Invalid configuration')

            expect do
              described_class.routes
            end.to raise_error(ArgumentError, /Failed to load routes from 'health_check' handler: Invalid configuration/)
          end

          it 'raises TypeError when a route handler returns non-Hash' do
            health_check_instance = instance_double(ForestAdminAgent::Routes::System::HealthCheck)
            allow(health_check_instance).to receive(:routes).and_return(nil)
            allow(ForestAdminAgent::Routes::System::HealthCheck).to receive(:new).and_return(health_check_instance)

            expect do
              described_class.routes
            end.to raise_error(TypeError, /Route handler 'health_check' returned NilClass instead of Hash/)
          end
        end
      end

      describe '.actions_routes' do
        it 'returns a hash' do
          routes = described_class.actions_routes
          expect(routes).to be_a(Hash)
        end

        it 'builds routes for each collection action' do
          routes = described_class.actions_routes

          Facades::Container.datasource.collections.each_value do |collection|
            collection.schema[:actions].each_key do |_action_name|
              action_routes = routes.select { |_name, route| route[:uri].include?(collection.name) }
              expect(action_routes).not_to be_empty if collection.schema[:actions].any?
            end
          end
        end
      end

      describe '.api_charts_routes' do
        it 'returns a hash' do
          routes = described_class.api_charts_routes
          expect(routes).to be_a(Hash)
        end

        it 'builds routes for collection charts' do
          routes = described_class.api_charts_routes

          Facades::Container.datasource.collections.each_value do |collection|
            collection.schema[:charts].each do |_chart_name|
              chart_routes = routes.select { |_name, route| route[:uri].include?(collection.name) }
              expect(chart_routes).not_to be_empty if collection.schema[:charts].any?
            end
          end
        end

        it 'builds routes for datasource charts' do
          routes = described_class.api_charts_routes

          Facades::Container.datasource.schema[:charts].each do |_chart_name|
            expect(routes).not_to be_empty if Facades::Container.datasource.schema[:charts].any?
          end
        end
      end

      describe 'cache behavior in different scenarios' do
        before do
          described_class.reset_cached_routes!
        end

        it 'prevents race condition during concurrent cache initialization' do
          call_count = 0
          call_mutex = Mutex.new

          allow(described_class).to receive(:routes).and_wrap_original do |m|
            # Add a small delay to increase chance of race condition
            sleep(0.01)
            call_mutex.synchronize { call_count += 1 }
            m.call
          end

          # Simulate multiple threads accessing cached_routes simultaneously
          threads = Array.new(20) do
            Thread.new { described_class.cached_routes }
          end

          results = threads.map(&:value)

          # routes() should only be called ONCE even with concurrent access
          expect(call_count).to eq(1), "Expected 1 call to routes() but got #{call_count}"

          # All results should be the identical object (same object_id)
          expect(results.map(&:object_id).uniq.size).to eq(1)
        end

        it 'handles concurrent access after cache is populated' do
          first_result = described_class.cached_routes

          # Simulate multiple threads accessing cached_routes
          threads = Array.new(10) do
            Thread.new { described_class.cached_routes }
          end

          results = threads.map(&:value)

          results.each do |result|
            expect(result.object_id).to eq(first_result.object_id)
          end
        end

        it 'maintains cache integrity after reset and reaccess' do
          initial_routes = described_class.cached_routes
          initial_keys = initial_routes.keys.sort

          described_class.reset_cached_routes!

          new_routes = described_class.cached_routes
          new_keys = new_routes.keys.sort

          expect(new_keys).to eq(initial_keys)
        end
      end

      describe 'configuration-driven caching' do
        before do
          described_class.reset_cached_routes!
        end

        after do
          allow(ForestAdminAgent::Facades::Container).to receive(:config_from_cache).and_call_original
          described_class.reset_cached_routes!
        end

        it 'enables caching by default when config is not set' do
          allow(ForestAdminAgent::Facades::Container).to receive(:config_from_cache).and_return({})

          expect(described_class.cache_disabled?).to be(false)
        end

        it 'enables caching by default when config is nil' do
          allow(ForestAdminAgent::Facades::Container).to receive(:config_from_cache).and_return(nil)

          expect(described_class.cache_disabled?).to be(false)
        end

        it 'disables caching when disable_route_cache is true' do
          allow(ForestAdminAgent::Facades::Container).to receive(:config_from_cache).and_return({ disable_route_cache: true })

          expect(described_class.cache_disabled?).to be(true)
        end

        it 'enables caching when disable_route_cache is false' do
          allow(ForestAdminAgent::Facades::Container).to receive(:config_from_cache).and_return({ disable_route_cache: false })

          expect(described_class.cache_disabled?).to be(false)
        end

        it 'enables caching by default when config access fails' do
          allow(ForestAdminAgent::Facades::Container).to receive(:config_from_cache).and_raise(StandardError, 'Config not available')

          expect(described_class.cache_disabled?).to be(false)
        end

        it 'returns fresh routes on every call when caching is disabled' do
          allow(ForestAdminAgent::Facades::Container).to receive(:config_from_cache).and_return({ disable_route_cache: true })

          first_routes = described_class.cached_routes
          first_object_id = first_routes.object_id

          second_routes = described_class.cached_routes
          second_object_id = second_routes.object_id

          expect(second_object_id).not_to eq(first_object_id)
        end

        it 'still returns frozen routes when caching is disabled' do
          allow(ForestAdminAgent::Facades::Container).to receive(:config_from_cache).and_return({ disable_route_cache: true })

          routes = described_class.cached_routes

          expect(routes).to be_frozen
        end

        it 'uses memoized cache when caching is enabled' do
          allow(ForestAdminAgent::Facades::Container).to receive(:config_from_cache).and_return({ disable_route_cache: false })

          first_routes = described_class.cached_routes
          first_object_id = first_routes.object_id

          second_routes = described_class.cached_routes
          second_object_id = second_routes.object_id

          expect(second_object_id).to eq(first_object_id)
        end
      end

      describe 'setup_routes caching' do
        before do
          described_class.reset_cached_routes!
        end

        it 'only instantiates route handlers once (setup_routes called once per handler)' do
          instantiation_count = 0
          instantiation_mutex = Mutex.new

          allow(ForestAdminAgent::Routes::System::HealthCheck).to receive(:new).and_wrap_original do |m|
            instantiation_mutex.synchronize { instantiation_count += 1 }
            m.call
          end

          described_class.cached_routes

          described_class.cached_routes

          described_class.cached_routes

          expect(instantiation_count).to eq(1), "Expected 1 HealthCheck instantiation but got #{instantiation_count}"
        end

        it 'calls setup_routes only once per handler across multiple cached_routes calls' do
          instantiation_count = 0
          instantiation_mutex = Mutex.new

          allow(ForestAdminAgent::Routes::Security::Authentication).to receive(:new).and_wrap_original do |m|
            instantiation_mutex.synchronize { instantiation_count += 1 }
            m.call
          end

          5.times { described_class.cached_routes }

          expect(instantiation_count).to eq(1), "Expected 1 Authentication instantiation but got #{instantiation_count}"
        end

        it 'recomputes and calls setup_routes again after cache reset' do
          instantiation_count = 0
          instantiation_mutex = Mutex.new

          allow(ForestAdminAgent::Routes::System::HealthCheck).to receive(:new).and_wrap_original do |m|
            instantiation_mutex.synchronize { instantiation_count += 1 }
            m.call
          end

          described_class.cached_routes
          expect(instantiation_count).to eq(1)

          described_class.reset_cached_routes!

          described_class.cached_routes
          expect(instantiation_count).to eq(2)
        end
      end
    end
  end
end
