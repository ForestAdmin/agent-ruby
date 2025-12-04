require 'spec_helper'

module ForestAdminRpcAgent
  describe SseConnectionManager do
    let(:logger) { instance_double(Logger, log: nil) }

    before do
      allow(ForestAdminRpcAgent::Facades::Container).to receive(:logger).and_return(logger)
      described_class.reset!
    end

    after do
      described_class.reset!
    end

    describe '.register_connection' do
      it 'returns a new connection' do
        connection = described_class.register_connection

        expect(connection).to be_a(SseConnectionManager::Connection)
        expect(connection.active?).to be true
      end

      it 'sets the connection as current' do
        connection = described_class.register_connection

        expect(described_class.current_connection).to eq(connection)
      end

      it 'terminates previous connection when a new one is registered' do
        first_connection = described_class.register_connection
        expect(first_connection.active?).to be true

        second_connection = described_class.register_connection

        expect(first_connection.active?).to be false
        expect(second_connection.active?).to be true
        expect(described_class.current_connection).to eq(second_connection)
      end

      it 'logs when terminating previous connection' do
        described_class.register_connection
        described_class.register_connection

        expect(logger).to have_received(:log).with('Debug', '[SSE ConnectionManager] Terminating previous connection')
      end

      it 'logs when registering new connection' do
        connection = described_class.register_connection

        expect(logger).to have_received(:log).with(
          'Debug',
          "[SSE ConnectionManager] New connection registered (id: #{connection.id})"
        )
      end
    end

    describe '.unregister_connection' do
      it 'clears current connection if it matches' do
        connection = described_class.register_connection
        described_class.unregister_connection(connection)

        expect(described_class.current_connection).to be_nil
      end

      it 'does not clear current connection if it does not match' do
        first_connection = described_class.register_connection
        second_connection = described_class.register_connection

        # Try to unregister the first (already replaced) connection
        described_class.unregister_connection(first_connection)

        # Second connection should still be current
        expect(described_class.current_connection).to eq(second_connection)
      end

      it 'logs when unregistering connection' do
        connection = described_class.register_connection
        described_class.unregister_connection(connection)

        expect(logger).to have_received(:log).with(
          'Debug',
          "[SSE ConnectionManager] Connection unregistered (id: #{connection.id})"
        )
      end
    end

    describe '.reset!' do
      it 'terminates and clears current connection' do
        connection = described_class.register_connection
        described_class.reset!

        expect(connection.active?).to be false
        expect(described_class.current_connection).to be_nil
      end
    end

    describe 'thread safety' do
      it 'handles concurrent registrations safely' do
        connections = []
        threads = Array.new(10) do
          Thread.new do
            connections << described_class.register_connection
          end
        end
        threads.each(&:join)

        # Only one connection should be active
        active_count = connections.count(&:active?)
        expect(active_count).to eq(1)

        # The current connection should be one of the registered ones
        expect(connections).to include(described_class.current_connection)
      end
    end
  end

  describe SseConnectionManager::Connection do
    describe '#initialize' do
      it 'creates an active connection with a unique id' do
        connection = described_class.new

        expect(connection.id).to be_a(String)
        expect(connection.id.length).to eq(36) # UUID format
        expect(connection.active?).to be true
      end

      it 'generates unique ids for each connection' do
        connection1 = described_class.new
        connection2 = described_class.new

        expect(connection1.id).not_to eq(connection2.id)
      end
    end

    describe '#terminate' do
      it 'marks the connection as inactive' do
        connection = described_class.new
        connection.terminate

        expect(connection.active?).to be false
      end

      it 'is idempotent' do
        connection = described_class.new
        connection.terminate
        connection.terminate

        expect(connection.active?).to be false
      end
    end

    describe '#active?' do
      it 'returns true for new connections' do
        connection = described_class.new

        expect(connection.active?).to be true
      end

      it 'returns false after termination' do
        connection = described_class.new
        connection.terminate

        expect(connection.active?).to be false
      end
    end
  end
end
