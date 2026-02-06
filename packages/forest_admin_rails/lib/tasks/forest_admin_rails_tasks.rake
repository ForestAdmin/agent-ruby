namespace :forest_admin do
  namespace :schema do
    desc 'Generate the Forest Admin schema file without starting the server or sending it to the API'
    task generate: :environment do
      require 'forest_admin_agent'

      output_path = ENV.fetch('output', nil)
      debug_mode = ENV['debug'] == 'true'

      puts '[ForestAdmin] Starting schema generation...'

      # Force eager loading of all models
      Rails.application.eager_load!

      # Check if create_agent.rb exists
      create_agent_path = Rails.root.join('lib', 'forest_admin_rails', 'create_agent.rb')
      unless File.exist?(create_agent_path)
        puts '[ForestAdmin] Error: create_agent.rb not found at lib/forest_admin_rails/create_agent.rb'
        puts '[ForestAdmin] Run `rails generate forest_admin_rails <ENV_SECRET>` to create it.'
        exit 1
      end

      # Setup the agent factory
      agent_factory = ForestAdminAgent::Builder::AgentFactory.instance
      agent_factory.setup(ForestAdminRails.config)

      # Enable schema-only mode (generates schema without sending to API)
      agent_factory.schema_only_mode = true
      agent_factory.schema_output_path = output_path if output_path

      # Load and execute the create_agent.rb file
      require create_agent_path

      # Call setup! which will generate the schema
      begin
        ForestAdminRails::CreateAgent.setup!
        puts '[ForestAdmin] Schema generation completed!'
      rescue StandardError => e
        puts "[ForestAdmin] Error during schema generation: #{e.message}"
        puts e.backtrace.first(10).join("\n") if debug_mode
        exit 1
      end
    end
  end
end
