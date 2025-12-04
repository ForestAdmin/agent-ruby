module ForestAdminRpcAgent
  # Manages SSE connections to ensure only one active connection at a time.
  # When a new connection is established, the previous one is terminated.
  # This prevents zombie loops when the master restarts and reconnects.
  class SseConnectionManager
    @mutex = Mutex.new
    @current_connection = nil

    class << self
      # Registers a new SSE connection and terminates any existing one.
      # Returns a connection object that can be used to check if the connection is still active.
      def register_connection
        connection = Connection.new

        @mutex.synchronize do
          # Terminate the previous connection if it exists
          if @current_connection
            ForestAdminRpcAgent::Facades::Container.logger&.log(
              'Debug',
              '[SSE ConnectionManager] Terminating previous connection'
            )
            @current_connection.terminate
          end

          @current_connection = connection
          ForestAdminRpcAgent::Facades::Container.logger&.log(
            'Debug',
            "[SSE ConnectionManager] New connection registered (id: #{connection.id})"
          )
        end

        connection
      end

      # Unregisters a connection when it's closed normally.
      def unregister_connection(connection)
        @mutex.synchronize do
          if @current_connection&.id == connection.id
            @current_connection = nil
            ForestAdminRpcAgent::Facades::Container.logger&.log(
              'Debug',
              "[SSE ConnectionManager] Connection unregistered (id: #{connection.id})"
            )
          end
        end
      end

      # Returns the current active connection (for testing purposes)
      def current_connection
        @mutex.synchronize { @current_connection }
      end

      # Resets the manager state (for testing purposes)
      def reset!
        @mutex.synchronize do
          @current_connection&.terminate
          @current_connection = nil
        end
      end
    end

    # Represents an individual SSE connection
    class Connection
      attr_reader :id

      def initialize
        @id = SecureRandom.uuid
        @active = true
        @mutex = Mutex.new
      end

      def active?
        @mutex.synchronize { @active }
      end

      def terminate
        @mutex.synchronize { @active = false }
      end
    end
  end
end
