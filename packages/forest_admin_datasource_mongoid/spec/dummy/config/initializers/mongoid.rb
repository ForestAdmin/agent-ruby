if defined?(Mongoid)
  Mongoid.configure do |config|
    target_version = "9.0"

    # Load Mongoid behavior defaults. This automatically sets
    # features flags (refer to documentation)
    config.load_defaults target_version

    # Optional: Set additional configuration values here
  end
else
  Rails.logger.warn("Mongoid is not loaded. Please ensure the gem is installed and required.")
end
