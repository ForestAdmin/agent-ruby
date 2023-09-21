require 'spec_helper'
require 'singleton'

module ForestAdminAgent
  module Routes
    module System
      describe HealthCheck do
        subject(:healthcheck) { described_class.new }

        before do
          agent_factory = ForestAdminAgent::Builder::AgentFactory.instance
          agent_factory.setup(
            {
              auth_secret: 'cba803d01a4d43b55010cab41fa1ea1f1f51a95e',
              env_secret: '89719c6d8e2e2de2694c2f220fe2dbf02d5289487364daf1e4c6b13733ed0cdb',
              is_production: false,
              cache_dir: 'tmp/cache/forest_admin'
            }
          )
        end

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
        end
      end
    end
  end
end
