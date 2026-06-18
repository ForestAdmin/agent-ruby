module ForestAdminAgent
  module Http
    # Rack middleware echoing the agent-generated correlation id back to the client, mirroring the
    # Node agent's `correlationIdMiddleware` (`router.use(...)`). Hosts mount it in their middleware
    # stack; CORS exposure of the header is handled by the host's CORS config (see the Rails engine).
    #
    # The id itself is generated lazily by the agent during the request (see CorrelationId, called
    # from CallerParser). This middleware only resets the thread-local around the request — so a
    # pooled thread never reuses a previous id — and sets the response header when one was generated.
    class CorrelationIdMiddleware
      def initialize(app)
        @app = app
      end

      def call(env)
        CorrelationId.reset!

        status, headers, body = @app.call(env)

        id = CorrelationId.current?
        headers[CorrelationId::HEADER] = id if id

        [status, headers, body]
      ensure
        CorrelationId.reset!
      end
    end
  end
end
