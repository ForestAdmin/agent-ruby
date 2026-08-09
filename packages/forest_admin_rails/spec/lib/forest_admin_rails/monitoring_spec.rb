require 'spec_helper'
require 'json'
require 'stringio'
require 'active_support'
require 'active_support/core_ext/string/filters'
require_relative '../../../lib/forest_admin_rails/monitoring'

module ForestAdminRails
  RSpec.describe Monitoring do
    let(:io) { StringIO.new }
    let(:logger) do
      Logger.new(io).tap { |l| l.formatter = proc { |_s, _t, _p, msg| "#{msg}\n" } }
    end
    let(:handles) { [] }

    after { handles.flatten.each { |h| ActiveSupport::Notifications.unsubscribe(h) } }

    def lines
      io.string.each_line.map(&:strip).reject(&:empty?)
    end

    it 'logs a forest event as tagged JSON with duration and payload' do
      handles.concat(described_class.subscribe!(logger, format: :json))

      ActiveSupport::Notifications.instrument('request.forest_admin', collection: 'user', id: '42') { nil }

      data = JSON.parse(lines.grep(/request\.forest_admin/).first)
      expect(data).to include(
        'source' => 'forest_admin', 'event' => 'request.forest_admin', 'collection' => 'user', 'id' => '42'
      )
      expect(data['duration_ms']).to be >= 0
    end

    it 'drops ignored events (hooks by default)' do
      handles.concat(described_class.subscribe!(logger))

      ActiveSupport::Notifications.instrument('hook.forest_admin', collection: 'user', operation: 'Create') { nil }

      expect(io.string).not_to include('hook.forest_admin')
    end

    it 'attaches the exception when an operation raises' do
      handles.concat(described_class.subscribe!(logger, format: :json))

      expect do
        ActiveSupport::Notifications.instrument('action.forest_admin', collection: 'user', action: 'ban') { raise 'boom' }
      end.to raise_error('boom')

      data = JSON.parse(lines.grep(/action\.forest_admin/).first)
      expect(data['error']).to eq('RuntimeError: boom')
    end

    it 'summarises SQL per request grouped by query name (off level)' do
      handles.concat(described_class.subscribe!(logger, sql_level: 'off'))

      ActiveSupport::Notifications.instrument('request.forest_admin', collection: 'user') do
        3.times { ActiveSupport::Notifications.instrument('sql.active_record', name: 'Subscription Load', sql: 'SELECT 1') { nil } }
        ActiveSupport::Notifications.instrument('sql.active_record', name: 'SCHEMA', sql: 'x') { nil } # skipped
        ActiveSupport::Notifications.instrument('sql.active_record', name: 'User Load', sql: 'SELECT 2', cached: true) { nil } # skipped
      end

      summary = JSON.parse(lines.grep(/sql\.summary/).first)
      expect(summary['queries']).to eq(3)
      expect(summary['breakdown']).to include(include('query' => 'Subscription Load', 'count' => 3))
    end

    it 'logs each query in full mode instead of summarising' do
      handles.concat(described_class.subscribe!(logger, sql_level: 'full'))

      ActiveSupport::Notifications.instrument('request.forest_admin', collection: 'user') do
        2.times { ActiveSupport::Notifications.instrument('sql.active_record', name: 'User Load', sql: 'SELECT 1') { nil } }
      end

      expect(lines.grep(/sql\.active_record/).size).to eq(2)
      expect(io.string).not_to include('sql.summary')
    end

    it 'does not log SQL that runs outside a forest request' do
      handles.concat(described_class.subscribe!(logger, sql_level: 'full'))

      ActiveSupport::Notifications.instrument('sql.active_record', name: 'User Load', sql: 'SELECT 1') { nil }

      expect(io.string).not_to include('sql.active_record')
    end
  end
end
