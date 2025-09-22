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

        form = collection.get_form(caller, action, data, filter, metas)
        form = encode_file_element(form)
        form.to_json
      end

      def encode_file_element(elements)
        nested_elements = %w[Page Row]
        elements.map do |element|
          encode_file_element(element) if element.type == 'Layout' && nested_elements.include?(element.component)

          if element.type == 'File' && element.value && element.value.is_a?(File)
            element.value = ForestAdminAgent::Utils::Schema::ForestValueConverter.make_data_uri(element.value)
          end

          element
        end
      end
    end
  end
end
