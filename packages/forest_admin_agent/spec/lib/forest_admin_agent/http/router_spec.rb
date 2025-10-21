require 'spec_helper'

module ForestAdminAgent
  module Http
    describe Router do
      describe '.cached_routes' do
        before do
          # Reset cache before each test
          described_class.reset_cached_routes!
        end

        after do
          # Clean up after tests
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
          # First call computes routes
          first_call = described_class.cached_routes
          first_object_id = first_call.object_id

          # Second call should return the same object (memoized)
          second_call = described_class.cached_routes
          second_object_id = second_call.object_id

          expect(second_object_id).to eq(first_object_id)
        end

        it 'does not recompute routes on subsequent calls' do
          # Spy on the routes method to ensure it's only called once
          allow(described_class).to receive(:routes).and_call_original

          # First call
          described_class.cached_routes

          # Second call
          described_class.cached_routes

          # routes should only be called once (for the first call)
          expect(described_class).to have_received(:routes).once
        end

        it 'includes standard routes from route handlers' do
          routes = described_class.cached_routes
          route_names = routes.keys.map(&:to_s)

          # Check that some expected routes exist (use actual route names)
          expect(route_names).to include('forest')
          expect(route_names).to include('forest_authentication')
        end
      end

      describe '.reset_cached_routes!' do
        before do
          # Ensure cache is reset
          described_class.reset_cached_routes!
        end

        it 'clears the cached routes' do
          # Cache some routes
          first_routes = described_class.cached_routes
          first_object_id = first_routes.object_id

          # Reset the cache
          described_class.reset_cached_routes!

          # Get routes again - should be a new object
          second_routes = described_class.cached_routes
          second_object_id = second_routes.object_id

          expect(second_object_id).not_to eq(first_object_id)
        end

        it 'allows routes to be recomputed after reset' do
          # Cache routes
          described_class.cached_routes

          # Reset cache
          described_class.reset_cached_routes!

          # Spy on routes method
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

          # Should not be empty
          expect(routes).not_to be_empty

          # Each route should have the expected structure
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
      end

      describe '.actions_routes' do
        it 'returns a hash' do
          routes = described_class.actions_routes
          expect(routes).to be_a(Hash)
        end

        it 'builds routes for each collection action' do
          routes = described_class.actions_routes

          # Iterate through datasource collections and verify their actions have routes
          Facades::Container.datasource.collections.each_value do |collection|
            collection.schema[:actions].each_key do |action_name|
              # Check that a route exists for this action
              # The exact route name format might vary, but there should be a route for this action
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
            collection.schema[:charts].each do |chart_name|
              # Check that routes related to this chart exist
              chart_routes = routes.select { |_name, route| route[:uri].include?(collection.name) }
              expect(chart_routes).not_to be_empty if collection.schema[:charts].any?
            end
          end
        end

        it 'builds routes for datasource charts' do
          routes = described_class.api_charts_routes

          Facades::Container.datasource.schema[:charts].each do |chart_name|
            # Check that routes for datasource-level charts exist
            # These won't have a collection name in the URI
            expect(routes).not_to be_empty if Facades::Container.datasource.schema[:charts].any?
          end
        end
      end

      describe 'cache behavior in different scenarios' do
        before do
          described_class.reset_cached_routes!
        end

        it 'handles concurrent access correctly' do
          # Simulate multiple threads accessing cached_routes
          threads = 5.times.map do
            Thread.new { described_class.cached_routes }
          end

          results = threads.map(&:value)

          # All threads should get the same cached object
          first_object_id = results.first.object_id
          results.each do |result|
            expect(result.object_id).to eq(first_object_id)
          end
        end

        it 'maintains cache integrity after reset and reaccess' do
          # Get initial routes
          initial_routes = described_class.cached_routes
          initial_keys = initial_routes.keys.sort

          # Reset cache
          described_class.reset_cached_routes!

          # Get routes again
          new_routes = described_class.cached_routes
          new_keys = new_routes.keys.sort

          # Routes should have the same structure (same keys)
          expect(new_keys).to eq(initial_keys)
        end
      end
    end
  end
end
