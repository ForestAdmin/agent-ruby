module ForestAdminDatasourcePylon
  # Holds a request until its endpoint has budget. A middleware rather than a
  # call in each client method: there is one code path for every request here,
  # where the client has twenty, and this one also catches the requests the
  # client never issues itself — the replays `retry` performs.
  class Throttle < Faraday::Middleware
    def initialize(app, limiter:, base_path: '')
      super(app)
      @limiter   = limiter
      @base_path = base_path.to_s
    end

    # Faraday hands over the path of the resolved url, so a base url mounted
    # under a subpath carries that prefix and no rule matches. It comes off
    # before the limiter sees the path.
    def call(env)
      @limiter.acquire(env.method, env.url.path.delete_prefix(@base_path))
      @app.call(env)
    end
  end
end
