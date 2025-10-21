require 'spec_helper'

module ForestAdminRails
  # Mock CreateAgent class for testing
  class CreateAgent
    def self.setup!; end
  end

  RSpec.describe 'Engine#load_configuration' do
    describe 'Rails::Server presence check' do
      context 'when Rails::Server is defined (running rails server)' do
        it 'calls ForestAdminRails::CreateAgent.setup!' do
          stub_const('Rails::Server', Class.new)
          create_agent_class = class_double(CreateAgent, setup!: nil)
          stub_const('ForestAdminRails::CreateAgent', create_agent_class)

          create_agent_class.setup! if defined?(::Rails::Server)

          expect(create_agent_class).to have_received(:setup!)
        end
      end

      context 'when Rails::Server is not defined (running rake tasks, migrations, etc.)' do
        it 'does not call ForestAdminRails::CreateAgent.setup!' do
          hide_const('Rails::Server')
          create_agent_class = class_double(CreateAgent, setup!: nil)
          stub_const('ForestAdminRails::CreateAgent', create_agent_class)

          create_agent_class.setup! if defined?(::Rails::Server)

          expect(create_agent_class).not_to have_received(:setup!)
        end

        it 'does not call setup when running "rails about"' do
          # When running `rails about`, Rails::Server is not defined
          hide_const('Rails::Server')
          stub_const('ARGV', ['about'])
          create_agent_class = class_double(CreateAgent, setup!: nil)
          stub_const('ForestAdminRails::CreateAgent', create_agent_class)

          create_agent_class.setup! if defined?(::Rails::Server)

          expect(create_agent_class).not_to have_received(:setup!)
        end

        it 'does not call setup when running "rails db:migrate"' do
          # When running `rails db:migrate`, Rails::Server is not defined
          hide_const('Rails::Server')
          stub_const('ARGV', ['db:migrate'])
          create_agent_class = class_double(CreateAgent, setup!: nil)
          stub_const('ForestAdminRails::CreateAgent', create_agent_class)

          create_agent_class.setup! if defined?(::Rails::Server)

          expect(create_agent_class).not_to have_received(:setup!)
        end

        it 'does not call setup when running "rails console"' do
          # When running `rails console`, Rails::Server is not defined
          hide_const('Rails::Server')
          stub_const('Rails::Console', Class.new)
          stub_const('ARGV', ['console'])
          create_agent_class = class_double(CreateAgent, setup!: nil)
          stub_const('ForestAdminRails::CreateAgent', create_agent_class)

          create_agent_class.setup! if defined?(::Rails::Server)

          expect(create_agent_class).not_to have_received(:setup!)
        end
      end
    end
  end
end
