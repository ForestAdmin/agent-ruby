module ForestAdminRails
  class CreateAgent
    def self.setup!
      datasource = ForestAdminDatasourceActiveRecord::Datasource.new(
        Rails.env.to_sym,
        support_polymorphic_relations: true,
        # live_query_connections: {
        #   'primary' => 'primary',
        #   'mysql' => 'mysql_db',
        # }
      )
      mongo_datasource = ForestAdminDatasourceMongoid::Datasource.new(options: { flatten_mode: 'none' })

      #rpc_datasource = ForestAdminDatasourceRpc.build({uri: 'http://0.0.0.0:5000'})
      #rpc_datasource2 = ForestAdminDatasourceRpc.build({uri: 'http://0.0.0.0:5001'})
      #rpc_datasource3 = ForestAdminDatasourceRpc.build({uri: 'http://127.0.0.1:5002', auth_secret: '083f924631d91358a52098158ff3890574922f4749dddbbb'})

      @agent = ForestAdminAgent::Builder::AgentFactory.instance
                                                      #.add_datasource(rpc_datasource2)
                                                      .add_datasource(datasource, rename: {
          'User' => 'Customer',
        })
                                                      # .add_datasource(mongo_datasource)

      customize
      @agent.build
    end

    def self.customize
      # Add a chart at the datasource level (new DSL syntax)
      @agent.chart :appointments do
        value 784, 760
      end

      # Customize the Customer collection (new DSL syntax)
      @agent.collection :Customer do |collection|
        # Rename fields
        collection.rename_field('lastname', 'last_name')
      end
    end
  end
end
