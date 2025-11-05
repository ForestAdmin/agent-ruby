ForestAdminRpcAgent::Engine.routes.draw do
  next if defined?(Rake) && Rake.respond_to?(:application) && Rake.application&.top_level_tasks&.any?

  begin
    # Use cached_route_instances to avoid recomputing routes during Rails initialization
    ForestAdminRpcAgent::Http::Router.cached_route_instances.each do |route_instance|
      route_instance.registered(self)
    end
  rescue StandardError => e
    error_message = "[ForestAdminRpcAgent] CRITICAL: Failed to initialize routes: #{e.class} - #{e.message}\n" \
                    "#{e.backtrace.join("\n")}"
    begin
      ForestAdminRpcAgent::Facades::Container.logger.log('Error', error_message)
    rescue StandardError
      puts error_message
    end
    raise e
  end
end
