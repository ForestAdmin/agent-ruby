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
        end
      end
    end
  end
end
