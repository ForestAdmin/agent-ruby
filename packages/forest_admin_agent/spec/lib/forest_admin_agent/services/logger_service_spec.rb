require 'spec_helper'

module ForestAdminAgent
  module Services
    describe LoggerService do
      describe 'default logger level' do
        it 'defaults to Info' do
          service = described_class.new

          expect(service.default_logger.level).to eq(Logger::INFO)
        end

        it 'applies the configured level to the default logger' do
          service = described_class.new('Warn')

          expect(service.default_logger.level).to eq(Logger::WARN)
        end

        it 'is case-insensitive, so the config-style lowercase levels work too' do
          service = described_class.new('debug')

          expect(service.default_logger.level).to eq(Logger::DEBUG)
        end

        it 'falls back to Info when given an unknown level' do
          service = described_class.new('nonsense')

          expect(service.default_logger.level).to eq(Logger::INFO)
        end
      end

      describe '#log' do
        it 'filters out messages below the configured level on the default logger' do
          # MonoLogger captures the $stdout object at construction time, so the service
          # has to be built inside the block for RSpec's stdout swap to reach its writes.
          expect do
            described_class.new('Warn').log('Info', 'hidden')
          end.not_to output(/hidden/).to_stdout
        end

        it 'still emits messages at or above the configured level' do
          expect do
            described_class.new('Warn').log('Warn', 'shown')
          end.to output(/shown/).to_stdout
        end

        it 'delegates to a custom logger regardless of logger_level' do
          custom_logger = 'proc { |severity, message| $stdout.puts "custom:#{severity}:#{message}" }' # rubocop:disable Lint/InterpolationCheck
          service = described_class.new('Error', custom_logger)

          expect { service.log('Info', 'hello') }.to output(/custom:1:hello/).to_stdout
        end
      end
    end
  end
end
