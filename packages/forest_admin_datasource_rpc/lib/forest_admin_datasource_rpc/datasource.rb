module ForestAdminDatasourceRpc
  class Datasource < ForestAdminDatasourceToolkit::Datasource
    def initialize(options, introspection)
      super()

      ForestAdminAgent::Facades::Container.logger.log(
        'Info',
        "Building Rpc Datasource with #{introspection[:collections].length} " \
        "collections and #{introspection[:charts].length} charts."
      )

      introspection[:collections].each do |schema|
        add_collection(Collection.new(self, schema[:name], options, schema))
      end

      @options = options
      @charts = introspection[:charts]
      @rpc_relations = introspection[:rpc_relations]

      @schema = { charts: @charts }
    end

    def render_chart(_caller, _name)
      # TODO
    end
  end
end
