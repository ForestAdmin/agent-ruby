require 'singleton'

module ForestAdminDatasourceRpc
  module Utils
    # Thread pool manager for RPC schema polling.
    # Uses a bounded pool of worker threads to poll multiple RPC datasources,
    # preventing thread exhaustion when many RPC slaves are configured.
    #
    # The pool uses a work queue pattern where polling tasks are scheduled
    # at staggered intervals to spread load evenly across time.
    class SchemaPollingPool
      include Singleton

      DEFAULT_MAX_THREADS = 1
      MIN_THREADS = 1
      MAX_THREADS = 20

      attr_reader :max_threads, :configured

      def initialize
        @mutex = Mutex.new
        @clients = {}
        @work_queue = Queue.new
        @workers = []
        @running = false
        @max_threads = DEFAULT_MAX_THREADS
        @shutdown_requested = false
        @configured = false
      end

      # Configure the pool before starting. Must be called before any clients register.
      # @param max_threads [Integer] Maximum number of worker threads (1-20)
      def configure(max_threads:)
        @mutex.synchronize do
          raise 'Cannot configure pool while running' if @running

          validated_max = max_threads.to_i.clamp(MIN_THREADS, MAX_THREADS)
          @max_threads = validated_max
          @configured = true

          log('Info', "[SchemaPollingPool] Configured with max_threads: #{@max_threads}")
        end
      end

      # Register a polling client with the pool.
      # The pool will manage polling for this client using worker threads.
      # @param client_id [String] Unique identifier for the client (typically the RPC URI)
      # @param client [SchemaPollingClient] The polling client instance
      # @return [Boolean] true if registered successfully, false if already registered
      # rubocop:disable Naming/PredicateMethod
      def register(client_id, client)
        @mutex.synchronize do
          if @clients.key?(client_id)
            log('Warn', "[SchemaPollingPool] Client #{client_id} already registered, skipping")
            return false
          end

          @clients[client_id] = {
            client: client,
            last_poll_at: nil,
            next_poll_at: calculate_initial_poll_time
          }

          log('Info', "[SchemaPollingPool] Registered client: #{client_id} (#{@clients.size} total clients)")

          # Start the pool if this is the first client
          start_pool unless @running

          # Schedule initial poll for this client
          schedule_poll(client_id)
        end

        true
      end

      # Unregister a polling client from the pool.
      # @param client_id [String] The client identifier to unregister
      # @return [Boolean] true if unregistered successfully, false if not found
      def unregister(client_id)
        @mutex.synchronize do
          unless @clients.key?(client_id)
            log('Debug', "[SchemaPollingPool] Client #{client_id} not found for unregister")
            return false
          end

          @clients.delete(client_id)
          log('Info', "[SchemaPollingPool] Unregistered client: #{client_id} (#{@clients.size} remaining)")

          # Stop the pool if no clients remain
          stop_pool if @clients.empty? && @running
        end

        true
      end
      # rubocop:enable Naming/PredicateMethod

      # Get the number of registered clients
      def client_count
        @mutex.synchronize { @clients.size }
      end

      # Check if the pool is currently running
      def running?
        @mutex.synchronize { @running }
      end

      # Stop all workers and clear the pool. Used for testing and shutdown.
      def shutdown!
        @mutex.synchronize do
          return unless @running

          @shutdown_requested = true
          stop_pool
          @clients.clear
          @shutdown_requested = false
        end
      end

      # Reset the pool to initial state. Primarily for testing.
      def reset!
        shutdown!
        @mutex.synchronize do
          @max_threads = DEFAULT_MAX_THREADS
          @configured = false
        end
      end

      private

      def start_pool
        return if @running

        @running = true
        @shutdown_requested = false

        # Calculate actual thread count based on clients and max
        thread_count = @clients.size.clamp(MIN_THREADS, @max_threads)

        log('Info',
            "[SchemaPollingPool] Starting pool with #{thread_count} worker threads for #{@clients.size} clients")

        thread_count.times do |i|
          @workers << Thread.new { worker_loop(i) }
        end

        # Start the scheduler thread
        @scheduler_thread = Thread.new { scheduler_loop }
      end

      def stop_pool
        return unless @running

        log('Info', '[SchemaPollingPool] Stopping pool...')

        @running = false

        # Signal workers to stop by pushing nil for each worker
        @workers.size.times { @work_queue << nil }

        # Wait for workers to finish (with timeout)
        @workers.each { |w| w.join(2) }
        @workers.clear

        # Stop scheduler
        @scheduler_thread&.join(2)
        @scheduler_thread = nil

        # Clear the queue
        @work_queue.clear

        log('Info', '[SchemaPollingPool] Pool stopped')
      end

      def worker_loop(worker_id)
        log('Debug', "[SchemaPollingPool] Worker #{worker_id} started")

        loop do
          # Block waiting for work
          task = @work_queue.pop

          # nil signals shutdown
          break if task.nil?

          client_id = task[:client_id]

          begin
            execute_poll(client_id)
          rescue StandardError => e
            log('Error',
                "[SchemaPollingPool] Worker #{worker_id} error polling #{client_id}: #{e.class} - #{e.message}")
          end
        end

        log('Debug', "[SchemaPollingPool] Worker #{worker_id} stopped")
      end

      def scheduler_loop
        log('Debug', '[SchemaPollingPool] Scheduler started')

        while @running
          sleep(1) # Check every second

          next unless @running

          @mutex.synchronize do
            now = Time.now

            @clients.each do |client_id, state|
              next if state[:next_poll_at].nil?
              next if now < state[:next_poll_at]

              # Time to poll this client
              schedule_poll(client_id)

              # Calculate next poll time
              interval = state[:client].instance_variable_get(:@polling_interval) || 600
              state[:next_poll_at] = now + interval
            end
          end
        end

        log('Debug', '[SchemaPollingPool] Scheduler stopped')
      end

      def schedule_poll(client_id)
        @work_queue << { client_id: client_id, scheduled_at: Time.now }
      end

      def execute_poll(client_id)
        client_state = @mutex.synchronize { @clients[client_id] }

        return unless client_state

        client = client_state[:client]
        return if client.nil? || client.closed

        log('Debug', "[SchemaPollingPool] Polling client: #{client_id}")

        # Call the client's check_schema method
        client.send(:check_schema)

        @mutex.synchronize do
          @clients[client_id][:last_poll_at] = Time.now if @clients[client_id]
        end
      end

      def calculate_initial_poll_time
        # Stagger initial polls to avoid thundering herd
        # Each new client gets a small random delay
        Time.now + rand(0.0..2.0)
      end

      def log(level, message)
        return unless defined?(ForestAdminAgent::Facades::Container)

        ForestAdminAgent::Facades::Container.logger&.log(level, message)
      rescue StandardError
        # Silently ignore logging errors
      end
    end
  end
end
