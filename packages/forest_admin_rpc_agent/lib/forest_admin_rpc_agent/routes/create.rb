require 'jsonapi-serializers'

module ForestAdminRpcAgent
  module Routes
    class Create < BaseRoute
      def initialize
        super('rpc/:collection_name/create', 'post', 'rpc_create')
      end

      def handle_request(args)
        return '{}' unless args[:params]['collection_name']

        caller = ForestAdminDatasourceToolkit::Components::Caller.new(
          **args[:params]['caller'].to_h.transform_keys(&:to_sym)
        )
        datasource = ForestAdminRpcAgent::Facades::Container.datasource
        collection = datasource.get_collection(args[:params]['collection_name'])

        collection.create(caller, args[:params]['data'])
      end
    end
  end
end
