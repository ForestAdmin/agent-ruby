ForestAdminRails.configure do |config|
  config.auth_secret = '<%= @auth_secret %>'
  config.env_secret = '<%= @env_secret %>'

  # Monitoring — log what the agent does (request latency, slow smart fields,
  # actions, hooks, SQL). Disabled by default. Uncomment to enable; output is
  # JSON on STDOUT (auto-collected by Datadog/CloudWatch/k8s) unless you point
  # `output` at a file path or your own Logger.
  # config.monitoring = {
  #   enabled: true,
  #   output: :stdout,        # :stdout | "log/forest_admin_monitoring.log" | a Logger
  #   format: :json,          # :json | :text
  #   sql_level: 'off',       # off | medium | full (full = one line per query; use temporarily)
  #   slow_threshold_ms: 0    # only log events at least this slow
  # }
end
