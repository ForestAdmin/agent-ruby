module ForestAdminRails
  class CreateAgent
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
    include ForestAdminDatasourceCustomizer::Decorators::Action
    include ForestAdminDatasourceCustomizer::Decorators::Action::Types
    include ForestAdminDatasourceCustomizer::Decorators::Computed

    def self.setup!
      datasource = ForestAdminDatasourceActiveRecord::Datasource.new(
        Rails.env.to_sym,
        # support_polymorphic_relations: true,
        # live_query_connections: {
        #   'primary' => 'primary',
        #   'mysql' => 'mysql_db',
        # }
      )
      mongo_datasource = ForestAdminDatasourceMongoid::Datasource.new(options: { flatten_mode: 'none' })

      rpc_datasource = ForestAdminDatasourceRpc.build({
        uri: 'http://0.0.0.0:5000',
        auth_secret: ENV['FOREST_AUTH_SECRET']
      })

      @agent = ForestAdminAgent::Builder::AgentFactory.instance
                                                      .add_datasource(rpc_datasource)
                                                      .add_datasource(datasource, rename: {
          'User' => 'Customer',
        })
                                                      # .add_datasource(mongo_datasource)

      # @agent.add_chart('appointments') do |_context, result_builder|
      #   result_builder.objective(235, 300)
      # end
      customize
      @agent.build
    end

    def self.customize
      # Chart 'appointments' is already defined in the RPC datasource (warehouse)
      # @agent.add_chart('appointments') do |context, result_builder|
      #   ds = context.datasource.get_collection('Customer')
      #   puts ds
      #   result_builder.value(784, 760)
      # end
      @agent.customize_collection('Customer') do |collection|
        collection.rename_field('lastname', 'last_name')
      end
      @agent.remove_collection('Customer')
    end
  end
end
