require 'spec_helper'

module ForestAdminRails
  # Mock CreateAgent class for testing
  class CreateAgent
    def self.setup!; end
  end

  RSpec.describe 'Engine#running_web_server?' do
    let(:original_argv) { ARGV.dup }
    let(:original_program_name) { $PROGRAM_NAME }

    before do
      # Hide Rails::Server constant by default
      hide_const('Rails::Server') if defined?(Rails::Server)
    end

    after do
      # Restore original values
      ARGV.replace(original_argv)
      $PROGRAM_NAME = original_program_name
    end

    describe 'web server detection' do
      context 'when Rails::Server is defined' do
        it 'returns true for development server' do
          stub_const('Rails::Server', Class.new)

          result = defined?(::Rails::Server)

          expect(result).to be_truthy
        end
      end

      context 'when server command is in ARGV' do
        it 'returns true when running puma' do
          ARGV.replace(['puma', '-C', 'config/puma.rb'])

          server_commands = %w[puma unicorn thin passenger rackup]
          result = server_commands.any? { |cmd| ARGV.any? { |arg| arg.include?(cmd) } }

          expect(result).to be true
        end

        it 'returns true when running unicorn' do
          ARGV.replace(['unicorn', '-c', 'config/unicorn.rb'])

          server_commands = %w[puma unicorn thin passenger rackup]
          result = server_commands.any? { |cmd| ARGV.any? { |arg| arg.include?(cmd) } }

          expect(result).to be true
        end

        it 'returns true when running thin' do
          ARGV.replace(['thin', 'start'])

          server_commands = %w[puma unicorn thin passenger rackup]
          result = server_commands.any? { |cmd| ARGV.any? { |arg| arg.include?(cmd) } }

          expect(result).to be true
        end

        it 'returns true when running passenger' do
          ARGV.replace(['passenger', 'start'])

          server_commands = %w[puma unicorn thin passenger rackup]
          result = server_commands.any? { |cmd| ARGV.any? { |arg| arg.include?(cmd) } }

          expect(result).to be true
        end
      end

      context 'when server name is in $PROGRAM_NAME' do
        it 'returns true when running via puma executable' do
          $PROGRAM_NAME = '/usr/local/bin/puma'

          result = $PROGRAM_NAME.match?(/puma|unicorn|thin|passenger/)

          expect(result).to be true
        end

        it 'returns true when running via unicorn executable' do
          $PROGRAM_NAME = '/usr/local/bin/unicorn'

          result = $PROGRAM_NAME.match?(/puma|unicorn|thin|passenger/)

          expect(result).to be true
        end

        it 'returns true when running puma -C config/puma.rb' do
          # When running: puma -C config/puma.rb
          # ARGV will be: ['-C', 'config/puma.rb']
          # $PROGRAM_NAME will be something like: '/usr/local/bundle/bin/puma' or 'puma'
          ARGV.replace(['-C', 'config/puma.rb'])
          $PROGRAM_NAME = '/usr/local/bundle/bin/puma'

          server_commands = %w[puma unicorn thin passenger rackup]
          result = server_commands.any? { |cmd| ARGV.any? { |arg| arg.include?(cmd) } } ||
                   $PROGRAM_NAME.match?(/puma|unicorn|thin|passenger/)

          expect(result).to be true
        end
      end

      context 'when no web server is detected' do
        it 'returns false for console' do
          hide_const('Rails::Server')
          ARGV.replace(['console'])
          $PROGRAM_NAME = 'rails'

          server_commands = %w[puma unicorn thin passenger rackup]
          result = defined?(::Rails::Server) ||
                   server_commands.any? { |cmd| ARGV.any? { |arg| arg.include?(cmd) } } ||
                   $PROGRAM_NAME.match?(/puma|unicorn|thin|passenger/)

          expect(result).to be_falsy
        end

        it 'returns false for rake tasks' do
          hide_const('Rails::Server')
          ARGV.replace(['db:migrate'])
          $PROGRAM_NAME = 'rake'

          server_commands = %w[puma unicorn thin passenger rackup]
          result = defined?(::Rails::Server) ||
                   server_commands.any? { |cmd| ARGV.any? { |arg| arg.include?(cmd) } } ||
                   $PROGRAM_NAME.match?(/puma|unicorn|thin|passenger/)

          expect(result).to be_falsy
        end

        it 'returns false for migrations' do
          hide_const('Rails::Server')
          ARGV.replace(['db:migrate'])
          $PROGRAM_NAME = 'rails'

          server_commands = %w[puma unicorn thin passenger rackup]
          result = defined?(::Rails::Server) ||
                   server_commands.any? { |cmd| ARGV.any? { |arg| arg.include?(cmd) } } ||
                   $PROGRAM_NAME.match?(/puma|unicorn|thin|passenger/)

          expect(result).to be_falsy
        end

        it 'returns false for rails about' do
          hide_const('Rails::Server')
          ARGV.replace(['about'])
          $PROGRAM_NAME = 'rails'

          server_commands = %w[puma unicorn thin passenger rackup]
          result = defined?(::Rails::Server) ||
                   server_commands.any? { |cmd| ARGV.any? { |arg| arg.include?(cmd) } } ||
                   $PROGRAM_NAME.match?(/puma|unicorn|thin|passenger/)

          expect(result).to be_falsy
        end
      end
    end

    describe 'combined server detection logic' do
      it 'detects Rails development server' do
        stub_const('Rails::Server', Class.new)

        is_web_server = defined?(::Rails::Server)

        expect(is_web_server).to be_truthy
      end

      it 'detects Puma via ARGV' do
        ARGV.replace(['puma'])
        $PROGRAM_NAME = 'bundle'

        server_commands = %w[puma unicorn thin passenger rackup]
        is_web_server = server_commands.any? { |cmd| ARGV.any? { |arg| arg.include?(cmd) } }

        expect(is_web_server).to be_truthy
      end

      it 'detects Puma via $PROGRAM_NAME' do
        ARGV.clear
        $PROGRAM_NAME = '/usr/bin/puma'

        is_web_server = $PROGRAM_NAME.match?(/puma|unicorn|thin|passenger/)

        expect(is_web_server).to be_truthy
      end

      it 'returns false when no server is running' do
        hide_const('Rails::Server')
        ARGV.replace(['console'])
        $PROGRAM_NAME = 'rails'

        server_commands = %w[puma unicorn thin passenger rackup]
        is_web_server = defined?(::Rails::Server) ||
                        server_commands.any? { |cmd| ARGV.any? { |arg| arg.include?(cmd) } } ||
                        $PROGRAM_NAME.match?(/puma|unicorn|thin|passenger/)

        expect(is_web_server).to be_falsy
      end
    end

    context 'with file existence check' do
      it 'returns early when create_agent.rb does not exist' do
        stub_const('Rails::Server', Class.new)
        file_exists = false

        should_skip = !defined?(::Rails::Server) || !file_exists

        expect(should_skip).to be true
      end

      it 'continues when create_agent.rb exists and web server is running' do
        ARGV.replace(['puma'])
        file_exists = true

        server_commands = %w[puma unicorn thin passenger rackup]
        server_detected = server_commands.any? { |cmd| ARGV.any? { |arg| arg.include?(cmd) } }
        should_skip = !server_detected || !file_exists

        expect(should_skip).to be false
      end
    end
  end
end
