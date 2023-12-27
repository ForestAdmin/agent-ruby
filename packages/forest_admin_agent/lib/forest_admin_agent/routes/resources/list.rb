require 'jsonapi-serializers'

module ForestAdminAgent
  module Routes
    module Resources
      class List < AbstractAuthenticatedRoute
        include ForestAdminAgent::Builder
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
        def setup_routes
          add_route('forest_list', 'get', '/:collection_name', ->(args) { handle_request(args) })

          self
        end

        def handle_request(args = {})
          build(args)
          @permissions.can?(:browse, @collection)
          filter = ForestAdminDatasourceToolkit::Components::Query::Filter.new(
            condition_tree: ConditionTreeFactory.intersect([
                                                             @permissions.get_scope(@collection),
                                                             ForestAdminAgent::Utils::QueryStringParser.parse_condition_tree(
                                                               @collection, args
                                                             )
                                                           ]),
            page: ForestAdminAgent::Utils::QueryStringParser.parse_pagination(args),
            search: ForestAdminAgent::Utils::QueryStringParser.parse_search(@collection, args),
            search_extended: ForestAdminAgent::Utils::QueryStringParser.parse_search_extended(args)
          )
          projection = ForestAdminAgent::Utils::QueryStringParser.parse_projection_with_pks(@collection, args)
          records = @collection.list(@caller, filter, projection)

          {
            name: args[:params]['collection_name'],
            content: JSONAPI::Serializer.serialize(
              records,
              is_collection: true,
              serializer: Serializer::ForestSerializer,
              include: projection.relations.keys,
              meta: handle_search_decorator(args[:params]['search'], records)
            )
          }
        end

        def handle_search_decorator(search_value, records)
          decorator = { decorators: [] }
          unless search_value.nil?
            records.each_with_index do |record, index|
              decorator[:decorators][index] = { id: Utils::Id.pack_id(@collection, record), search: [] }
              record.attributes.each do |field_key, field_value|
                if !field_value.is_a?(Array) && field_value.to_s.downcase.include?(search_value.downcase)
                  decorator[:decorators][index][:search] << field_key
                end
              end
            end
          end

          decorator
        end
      end
    end
  end
end
