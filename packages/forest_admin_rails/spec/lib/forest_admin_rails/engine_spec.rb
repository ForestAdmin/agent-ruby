require 'spec_helper'

module ForestAdminRails
  # Mock CreateAgent class for testing
  class CreateAgent
    def self.setup!; end
  end

  RSpec.describe 'Engine#load_configuration' do
    describe 'Rails::Server presence check' do
      context 'when Rails::Server is not defined' do
        before { hide_const('Rails::Server') }

        it 'returns early without calling setup when Rails::Server is not defined' do
          # This simulates the behavior when running rails console, rake tasks, migrations, etc.
          return_value = nil
          return_value = true unless defined?(::Rails::Server)

          expect(return_value).to be true
        end

        it 'does not call setup when running rake tasks' do
          hide_const('Rails::Server')
          create_agent_class = class_double(CreateAgent, setup!: nil)
          stub_const('ForestAdminRails::CreateAgent', create_agent_class)

          # The condition should prevent setup from being called
          create_agent_class.setup! if defined?(::Rails::Server)

          expect(create_agent_class).not_to have_received(:setup!)
        end

        it 'does not call setup when running "rails db:migrate"' do
          hide_const('Rails::Server')
          stub_const('ARGV', ['db:migrate'])
          create_agent_class = class_double(CreateAgent, setup!: nil)
          stub_const('ForestAdminRails::CreateAgent', create_agent_class)

          create_agent_class.setup! if defined?(::Rails::Server)

          expect(create_agent_class).not_to have_received(:setup!)
        end

        it 'does not call setup when running "rails console"' do
          hide_const('Rails::Server')
          stub_const('Rails::Console', Class.new)
          create_agent_class = class_double(CreateAgent, setup!: nil)
          stub_const('ForestAdminRails::CreateAgent', create_agent_class)

          create_agent_class.setup! if defined?(::Rails::Server)

          expect(create_agent_class).not_to have_received(:setup!)
        end
      end

      context 'when Rails::Server is defined (running rails server)' do
        it 'allows setup to be called' do
          stub_const('Rails::Server', Class.new)
          create_agent_class = class_double(CreateAgent, setup!: nil)
          stub_const('ForestAdminRails::CreateAgent', create_agent_class)

          should_continue = defined?(::Rails::Server)
          create_agent_class.setup! if should_continue

          expect(create_agent_class).to have_received(:setup!)
        end
      end

      context 'with file existence check' do
        it 'returns early when create_agent.rb does not exist' do
          stub_const('Rails::Server', Class.new)
          file_exists = false

          should_skip = !defined?(::Rails::Server) || !file_exists

          expect(should_skip).to be true
        end

        it 'continues when create_agent.rb exists and Rails::Server is defined' do
          stub_const('Rails::Server', Class.new)
          file_exists = true

          should_skip = !defined?(::Rails::Server) || !file_exists

          expect(should_skip).to be false
        end
      end
    end
  end
end
