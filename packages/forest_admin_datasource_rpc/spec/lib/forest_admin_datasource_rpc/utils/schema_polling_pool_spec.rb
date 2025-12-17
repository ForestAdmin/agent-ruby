require 'spec_helper'

module ForestAdminDatasourceRpc
  module Utils
    describe SchemaPollingPool do
      let(:logger) { instance_spy(Logger) }
      let(:pool) { described_class.instance }

      before do
        allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(logger)
        # Reset pool state before each test
        pool.reset!
      end

      after do
        # Ensure clean shutdown after each test
        pool.shutdown!
      end

      describe '#configure' do
        it 'sets max_threads within valid range' do
          pool.configure(max_threads: 10)
          expect(pool.max_threads).to eq(10)
        end

        it 'enforces minimum of 1 thread' do
          pool.configure(max_threads: 0)
          expect(pool.max_threads).to eq(1)
        end

        it 'enforces maximum of 20 threads' do
          pool.configure(max_threads: 50)
          expect(pool.max_threads).to eq(20)
        end

        it 'raises error if pool is already running' do
          client = create_mock_client('http://test1:5000')
          pool.register('test1', client)

          expect { pool.configure(max_threads: 10) }.to raise_error(RuntimeError, /Cannot configure pool while running/)
        end

        it 'logs configuration' do
          pool.configure(max_threads: 8)
          expect(logger).to have_received(:log).with('Info', /Configured with max_threads: 8/)
        end
      end

      describe '#register' do
        it 'registers a client and starts the pool' do
          client = create_mock_client('http://test1:5000')

          result = pool.register('test1', client)

          expect(result).to be true
          expect(pool.client_count).to eq(1)
          expect(pool.running?).to be true
        end

        it 'allows multiple clients to be registered' do
          client1 = create_mock_client('http://test1:5000')
          client2 = create_mock_client('http://test2:5000')

          pool.register('test1', client1)
          pool.register('test2', client2)

          expect(pool.client_count).to eq(2)
        end

        it 'rejects duplicate client_id registration' do
          client1 = create_mock_client('http://test1:5000')
          client2 = create_mock_client('http://test1:5000')

          pool.register('test1', client1)
          result = pool.register('test1', client2)

          expect(result).to be false
          expect(pool.client_count).to eq(1)
        end

        it 'logs registration' do
          client = create_mock_client('http://test1:5000')
          pool.register('test1', client)

          expect(logger).to have_received(:log).with('Info', /Registered client: test1/)
        end
      end

      describe '#unregister' do
        it 'removes a registered client' do
          client = create_mock_client('http://test1:5000')
          pool.register('test1', client)

          result = pool.unregister('test1')

          expect(result).to be true
          expect(pool.client_count).to eq(0)
        end

        it 'returns false for unknown client_id' do
          result = pool.unregister('unknown')
          expect(result).to be false
        end

        it 'stops the pool when last client is removed' do
          client = create_mock_client('http://test1:5000')
          pool.register('test1', client)
          expect(pool.running?).to be true

          pool.unregister('test1')

          expect(pool.running?).to be false
        end

        it 'logs unregistration' do
          client = create_mock_client('http://test1:5000')
          pool.register('test1', client)
          pool.unregister('test1')

          expect(logger).to have_received(:log).with('Info', /Unregistered client: test1/)
        end
      end

      describe '#client_count' do
        it 'returns 0 initially' do
          expect(pool.client_count).to eq(0)
        end

        it 'tracks registered clients' do
          3.times do |i|
            client = create_mock_client("http://test#{i}:5000")
            pool.register("test#{i}", client)
          end

          expect(pool.client_count).to eq(3)
        end
      end

      describe '#running?' do
        it 'returns false when no clients registered' do
          expect(pool.running?).to be false
        end

        it 'returns true after first client registers' do
          client = create_mock_client('http://test1:5000')
          pool.register('test1', client)

          expect(pool.running?).to be true
        end
      end

      describe '#shutdown!' do
        it 'stops all workers and clears clients' do
          client1 = create_mock_client('http://test1:5000')
          client2 = create_mock_client('http://test2:5000')
          pool.register('test1', client1)
          pool.register('test2', client2)

          pool.shutdown!

          expect(pool.running?).to be false
          expect(pool.client_count).to eq(0)
        end

        it 'is idempotent' do
          client = create_mock_client('http://test1:5000')
          pool.register('test1', client)

          expect { pool.shutdown! }.not_to raise_error
          expect { pool.shutdown! }.not_to raise_error
        end
      end

      describe '#reset!' do
        it 'resets max_threads to default (1)' do
          pool.configure(max_threads: 15)
          pool.reset!

          expect(pool.max_threads).to eq(1)
          expect(pool.configured).to be false
        end
      end

      describe '#configured' do
        it 'is false initially' do
          expect(pool.configured).to be false
        end

        it 'is true after configure is called' do
          pool.configure(max_threads: 5)
          expect(pool.configured).to be true
        end
      end

      describe 'thread pool sizing' do
        it 'starts pool on first client registration' do
          pool.configure(max_threads: 10)

          client = create_mock_client('http://test0:5000')
          pool.register('test0', client)

          # Pool starts with 1 thread for 1 client (min of client count and max_threads)
          expect(logger).to have_received(:log).with('Info', /Starting pool with 1 worker threads for 1 clients/)
        end

        it 'handles many clients with bounded thread count' do
          pool.configure(max_threads: 3)

          # Register 10 clients
          10.times do |i|
            client = create_mock_client("http://test#{i}:5000")
            pool.register("test#{i}", client)
          end

          # Pool starts on first registration, subsequent registrations don't restart
          expect(logger).to have_received(:log).with('Info', /Starting pool with 1 worker threads for 1 clients/)
          expect(pool.client_count).to eq(10)
          expect(pool.running?).to be true
        end
      end

      describe 'polling execution' do
        it 'executes check_schema on registered clients' do
          client = create_mock_client('http://test1:5000')

          pool.register('test1', client)

          # Wait for scheduler to run
          sleep(2.5)

          expect(client).to have_received(:send).with(:check_schema).at_least(:once)
        end

        it 'handles errors in polling gracefully' do
          client = create_mock_client('http://test1:5000')
          allow(client).to receive(:send).with(:check_schema).and_raise(StandardError, 'Test error')

          pool.register('test1', client)

          # Wait for scheduler and verify pool stays running
          sleep(2.5)
          expect(pool.running?).to be true
        end

        it 'skips closed clients' do
          client = create_mock_client('http://test1:5000')
          allow(client).to receive(:closed).and_return(true)

          pool.register('test1', client)
          sleep(2.5)

          expect(client).not_to have_received(:send).with(:check_schema)
        end
      end

      describe 'integration: multiple clients with staggered polling' do
        it 'polls multiple clients through the thread pool' do
          poll_counts = { 'test1' => 0, 'test2' => 0, 'test3' => 0 }

          3.times do |i|
            client_id = "test#{i + 1}"
            client = create_mock_client("http://#{client_id}:5000", polling_interval: 1)
            allow(client).to receive(:send).with(:check_schema) do
              poll_counts[client_id] += 1
            end
            pool.register(client_id, client)
          end

          # Wait for initial staggered polls + one interval
          sleep(3)

          # All clients should have been polled at least once
          poll_counts.each do |client_id, count|
            expect(count).to be >= 1, "Expected #{client_id} to be polled at least once, got #{count}"
          end
        end
      end

      private

      def create_mock_client(uri, polling_interval: 600)
        client = instance_double(SchemaPollingClient)
        allow(client).to receive_messages(closed: false, client_id: uri)
        allow(client).to receive(:instance_variable_get).with(:@polling_interval).and_return(polling_interval)
        allow(client).to receive(:send).with(:check_schema)
        client
      end
    end
  end
end
