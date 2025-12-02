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
        return {} unless args[:params]['collection_name']

        datasource = ForestAdminRpcAgent::Facades::Container.datasource
        collection = get_collection_safe(datasource, args[:params]['collection_name'])
        filter = FilterFactory.from_plain_object(args[:params]['filter'])
        metas = args[:params]['metas'] || {}
        data = args[:params]['data']
        action = args[:params]['action']

        form = collection.get_form(args[:caller], action, data, filter, metas)
        encode_file_element(form)
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
