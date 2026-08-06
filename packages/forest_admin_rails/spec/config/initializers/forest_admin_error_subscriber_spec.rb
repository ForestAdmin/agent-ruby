require 'spec_helper'
require 'logger'

require_relative '../../../config/initializers/forest_admin_error_subscriber'

RSpec.describe ForestAdminErrorSubscriber do
  subject(:subscriber) { described_class.new }

  let(:logger) { instance_double(Logger, log: nil) }
  let(:error) { StandardError.new('envSecret invalid') }

  before do
    logger_double = logger
    container = Class.new
    container.define_singleton_method(:logger) { logger_double }
    stub_const('ForestAdminAgent::Facades::Container', container)
  end

  it 'logs the error even when running in production' do
    subscriber.report(error, handled: true, severity: :error, context: {})

    expect(logger).to have_received(:log).with('Error', /envSecret invalid/)
  end

  it 'maps each Rails error severity to the matching Forest logger level' do
    subscriber.report(error, handled: true, severity: :error, context: {})
    expect(logger).to have_received(:log).with('Error', anything)

    subscriber.report(error, handled: true, severity: :warning, context: {})
    expect(logger).to have_received(:log).with('Warn', anything)

    subscriber.report(error, handled: true, severity: :info, context: {})
    expect(logger).to have_received(:log).with('Info', anything)
  end

  it 'defaults to Error when given an unknown severity' do
    subscriber.report(error, handled: true, severity: :unknown, context: {})

    expect(logger).to have_received(:log).with('Error', anything)
  end
end
