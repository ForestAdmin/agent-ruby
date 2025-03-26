module ForestAdminRails
  class CreateAgent
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
    include ForestAdminDatasourceCustomizer::Decorators::Action
    include ForestAdminDatasourceCustomizer::Decorators::Action::Types
    include ForestAdminDatasourceCustomizer::Decorators::Computed
    include ForestAdminDatasourceToolkit::Components::Query

    def self.setup!
      # datasource = ForestAdminDatasourceActiveRecord::Datasource.new(
      #   Rails.env.to_sym,
      #   # support_polymorphic_relations: true,
      #   # live_query_connections: {
      #   #   'primary' => 'primary',
      #   #   'mysql' => 'mysql_db',
      #   # }
      # )
      # mongo_datasource = ForestAdminDatasourceMongoid::Datasource.new(options: { flatten_mode: 'none' })

      rpc_datasource = ForestAdminDatasourceRpc.build({uri: 'http://0.0.0.0:5000'})

      @agent = ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(rpc_datasource)
                                     # .add_datasource(datasource)
      # debugger
      ForestAdminRpcAgent::Agent.instance.mark_collections_as_rpc('product')
      ForestAdminDatasourceRpc.generate_rpc_relations(@agent.customizer)
      # customize
      @agent.build
    end

    def self.customize
    end
  end
end
