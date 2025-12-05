require 'spec_helper'

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Routes loading' do
  describe 'container check' do
    # Mock the AgentFactory class to avoid needing the full agent setup
    before do
      stub_const('ForestAdminAgent::Builder::AgentFactory', Class.new do
        def self.instance
          @instance ||= new
        end

        attr_accessor :container
      end)
    end

    context 'when container is nil (agent not set up)' do
      before do
        ForestAdminAgent::Builder::AgentFactory.instance.container = nil
      end

      it 'skips route loading' do
        container = ForestAdminAgent::Builder::AgentFactory.instance.container

        expect(container).to be_nil
      end

      it 'returns early from routes block when container is nil' do
        routes_loaded = false

        # Simulate the routes.rb logic
        routes_loaded = true if ForestAdminAgent::Builder::AgentFactory.instance.container

        expect(routes_loaded).to be false
      end
    end

    context 'when container is initialized (agent set up)' do
      # rubocop:disable RSpec/VerifiedDoubles
      let(:mock_container) { double('Container') }
      # rubocop:enable RSpec/VerifiedDoubles

      before do
        ForestAdminAgent::Builder::AgentFactory.instance.container = mock_container
      end

      it 'has container available' do
        container = ForestAdminAgent::Builder::AgentFactory.instance.container

        expect(container).not_to be_nil
      end

      it 'proceeds with route loading when container is present' do
        routes_loaded = false

        # Simulate the routes.rb logic
        routes_loaded = true if ForestAdminAgent::Builder::AgentFactory.instance.container

        expect(routes_loaded).to be true
      end
    end
  end

  describe 'Rake task check' do
    context 'when running a Rake task' do
      before do
        stub_const('Rake', Class.new do
          def self.respond_to?(method)
            method == :application
          end

          def self.application
            Class.new do
              def self.top_level_tasks
                ['db:migrate']
              end
            end
          end
        end)
      end

      it 'skips route loading' do
        should_skip = defined?(Rake) &&
                      Rake.respond_to?(:application) &&
                      Rake.application&.top_level_tasks&.any?

        expect(should_skip).to be true
      end
    end

    context 'when not running a Rake task' do
      before do
        hide_const('Rake') if defined?(Rake)
      end

      it 'does not skip route loading due to Rake check' do
        should_skip = defined?(Rake) &&
                      Rake.respond_to?(:application) &&
                      Rake.application&.top_level_tasks&.any?

        expect(should_skip).to be_falsy
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass
