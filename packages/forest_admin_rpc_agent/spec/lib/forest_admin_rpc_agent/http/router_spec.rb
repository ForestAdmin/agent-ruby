require 'spec_helper'

module ForestAdminRpcAgent
  module Http
    describe Router do
      before do
        # Reset cache before each test
        described_class.reset_cached_route_instances!
      end

      describe '.route_instances' do
        it 'returns an array of route instances' do
          routes = described_class.route_instances
          expect(routes).to be_an(Array)
          expect(routes).not_to be_empty
        end

        it 'excludes BaseRoute from instances' do
          routes = described_class.route_instances
          base_routes = routes.select { |r| r.instance_of?(ForestAdminRpcAgent::Routes::BaseRoute) }
          expect(base_routes).to be_empty
        end

        it 'only includes routes that respond to :registered' do
          routes = described_class.route_instances
          expect(routes).to all(respond_to(:registered))
        end
      end

      describe '.cached_route_instances' do
        context 'when cache is enabled' do
          before do
            allow(described_class).to receive(:cache_disabled?).and_return(false)
          end

          it 'returns frozen array' do
            routes = described_class.cached_route_instances
            expect(routes).to be_frozen
          end

          it 'returns the same object on subsequent calls' do
            first_call = described_class.cached_route_instances
            second_call = described_class.cached_route_instances
            expect(first_call.object_id).to eq(second_call.object_id)
          end

          it 'logs the computation time' do
            logger = instance_double(Logger)
            allow(ForestAdminRpcAgent::Facades::Container).to receive(:logger).and_return(logger)
            allow(logger).to receive(:log)
            described_class.cached_route_instances
            expect(logger).to have_received(:log).with(
              'Info',
              a_string_matching(/\[ForestAdminRpcAgent\] Computed \d+ routes in \d+\.\d+ms \(caching enabled\)/)
            )
          end
        end

        context 'when cache is disabled' do
          before do
            allow(described_class).to receive(:cache_disabled?).and_return(true)
          end

          it 'returns frozen array but does not cache' do
            routes = described_class.cached_route_instances
            expect(routes).to be_frozen
          end

          it 'returns different objects on subsequent calls' do
            first_call = described_class.cached_route_instances
            second_call = described_class.cached_route_instances
            expect(first_call.object_id).not_to eq(second_call.object_id)
          end
        end
      end

      describe '.reset_cached_route_instances!' do
        it 'clears the cache' do
          allow(described_class).to receive(:cache_disabled?).and_return(false)

          first_call = described_class.cached_route_instances
          described_class.reset_cached_route_instances!
          second_call = described_class.cached_route_instances

          expect(first_call.object_id).not_to eq(second_call.object_id)
        end
      end

      describe '.cache_disabled?' do
        context 'when disable_route_cache is true in config' do
          before do
            allow(ForestAdminRpcAgent::Facades::Container).to receive(:config_from_cache).and_return(
              { disable_route_cache: true }
            )
          end

          it 'returns true' do
            expect(described_class.cache_disabled?).to be true
          end
        end

        context 'when disable_route_cache is false in config' do
          before do
            allow(ForestAdminRpcAgent::Facades::Container).to receive(:config_from_cache).and_return(
              { disable_route_cache: false }
            )
          end

          it 'returns false' do
            expect(described_class.cache_disabled?).to be false
          end
        end

        context 'when config is not available' do
          before do
            allow(ForestAdminRpcAgent::Facades::Container).to receive(:config_from_cache).and_raise(StandardError)
          end

          it 'returns false (cache enabled by default)' do
            expect(described_class.cache_disabled?).to be false
          end
        end
      end
    end
  end
end
