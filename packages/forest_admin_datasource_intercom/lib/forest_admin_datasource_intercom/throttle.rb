module ForestAdminDatasourceIntercom
  # Holds a request until the rate-limit window has room, and feeds the window
  # back what the response says about it. A middleware rather than a call in
  # each client method: there is one code path for every request here, where the
  # client has one per endpoint, and this one also covers the requests the client
  # never issues itself -- the replays `retry` performs.
  class Throttle < Faraday::Middleware
    def initialize(app, limiter:)
      super(app)
      @limiter = limiter
    end

    def call(env)
      @limiter.acquire

      @app.call(env).on_complete { |response_env| @limiter.observe(response_env[:response_headers]) }
    end
  end
end
