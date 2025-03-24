require 'jsonapi-serializers'

module ForestAdminRpcAgent
  module Routes
    class ActionForm < BaseRoute
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminAgent::Utils
      include ForestAdminAgent::Routes::QueryHandler

      def initialize
        super('rpc/:collection_name/action-form', 'post', 'rpc_action_form')
      end

      def handle_request(args)
        return '{}' unless args[:params]['collection_name']

        datasource = ForestAdminRpcAgent::Facades::Container.datasource
        collection = datasource.get_collection(args[:params]['collection_name'])

        caller = if args[:params].key?('caller')
                   ForestAdminDatasourceToolkit::Components::Caller.new(
                     **args[:params]['caller'].to_h.transform_keys(&:to_sym)
                   )
                 end
        filter = FilterFactory.from_plain_object(args[:params]['filter'])
        metas = args[:params]['metas'] || {}
        data = args[:params]['data']
        action = args[:params]['action']

        collection.get_form(caller, action, data, filter, metas).to_json
      end
    end
  end
end
