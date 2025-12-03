require 'jsonapi-serializers'

module ForestAdminRpcAgent
  module Routes
    class Create < BaseRoute
      def initialize
        super('rpc/:collection_name/create', 'post', 'rpc_create')
      end

      def handle_request(args)
        return {} unless args[:params]['collection_name']

        datasource = ForestAdminRpcAgent::Facades::Container.datasource
        collection = get_collection_safe(datasource, args[:params]['collection_name'])

        [collection.create(args[:caller], args[:params]['data'].first)]
      end
    end
  end
end
