require 'spec_helper'
require 'singleton'

module ForestAdminAgent
  module Routes
    module System
      describe HealthCheck do
        subject(:healthcheck) { described_class.new }

        context 'when testing the HealthCheck class' do
          it 'returns an empty content and a 204 status' do
            result = healthcheck.handle_request
            expect(result[:content]).to be_nil
            expect(result[:status]).to eq 204
          end

          it 'adds the route forest' do
            healthcheck.setup_routes
            expect(healthcheck.routes.include?('forest')).to be true
            expect(healthcheck.routes.length).to eq 1
          end

          context 'when in production mode' do
            it 'forces schema send when skip_schema_update is disabled' do
              factory = instance_double(Builder::AgentFactory)
              cache = instance_double(FileCache)
              container = instance_double(Dry::Container)

              allow(Builder::AgentFactory).to receive(:instance).and_return(factory)
              allow(factory).to receive(:container).and_return(container)
              allow(container).to receive(:resolve).with(:cache).and_return(cache)
              allow(cache).to receive(:get).with('config').and_return({ is_production: true, skip_schema_update: false })
              allow(factory).to receive(:send_schema)

              result = healthcheck.handle_request

              expect(factory).to have_received(:send_schema).with(force: true)
              expect(result[:status]).to eq 204
            end

            it 'does not force schema send when skip_schema_update is enabled' do
              factory = instance_double(Builder::AgentFactory)
              cache = instance_double(FileCache)
              container = instance_double(Dry::Container)

              allow(Builder::AgentFactory).to receive(:instance).and_return(factory)
              allow(factory).to receive(:container).and_return(container)
              allow(container).to receive(:resolve).with(:cache).and_return(cache)
              allow(cache).to receive(:get).with('config').and_return({ is_production: true, skip_schema_update: true })
              allow(factory).to receive(:send_schema)

              result = healthcheck.handle_request

              expect(factory).not_to have_received(:send_schema)
              expect(result[:status]).to eq 204
            end
          end

          context 'when not in production mode' do
            it 'does not force schema send' do
              factory = instance_double(Builder::AgentFactory)
              cache = instance_double(FileCache)
              container = instance_double(Dry::Container)

              allow(Builder::AgentFactory).to receive(:instance).and_return(factory)
              allow(factory).to receive(:container).and_return(container)
              allow(container).to receive(:resolve).with(:cache).and_return(cache)
              allow(cache).to receive(:get).with('config').and_return({ is_production: false })
              allow(factory).to receive(:send_schema)

              result = healthcheck.handle_request

              expect(factory).not_to have_received(:send_schema)
              expect(result[:status]).to eq 204
            end
          end
        end
      end
    end
  end
end
