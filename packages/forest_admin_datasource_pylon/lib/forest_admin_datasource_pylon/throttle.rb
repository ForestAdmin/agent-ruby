module ForestAdminDatasourcePylon
  # Holds a request until its endpoint has budget. A middleware rather than a
  # call in each client method: there is one code path for every request here,
  # where the client has twenty, and this one also catches the requests the
  # client never issues itself — the replays `retry` performs.
  class Throttle < Faraday::Middleware
    def initialize(app, limiter:)
      super(app)
      @limiter = limiter
    end

    def call(env)
      @limiter.acquire(env.method, env.url.path)
      @app.call(env)
    end
  end
end
