require 'jsonapi-serializers'

module ForestAdminAgent
  module Routes
    module Resources
      class List < AbstractAuthenticatedRoute
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
        include ForestAdminAgent::Utils

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
            page: QueryStringParser.parse_pagination(args),
            search: QueryStringParser.parse_search(@collection, args),
            search_extended: QueryStringParser.parse_search_extended(args),
            sort: QueryStringParser.parse_sort(@collection, args),
            segment: QueryStringParser.parse_segment(@collection, args),
            segment_query: QueryStringParser.parse_query_segment(args)
          )

          projection = QueryStringParser.parse_projection_with_pks(@collection, args)
          records = @collection.list(@caller, filter, projection)

          {
            name: args[:params]['collection_name'],
            content: JSONAPI::Serializer.serialize(
              records,
              class_name: @collection.name,
              is_collection: true,
              serializer: Serializer::ForestSerializer,
              include: projection.relations(only_keys: true),
              meta: handle_search_decorator(args[:params]['search'], records)
            )
          }
        end

        def handle_search_decorator(search_value, records)
          decorator = { decorators: [] }
          unless search_value.nil?
            records.each_with_index do |entry, index|
              decorator[:decorators][index] = { id: Utils::Id.pack_id(@collection, entry), search: [] }
              # attributes method is defined on ActiveRecord::Base model
              attributes = entry.respond_to?(:attributes) ? entry.attributes : entry

              attributes.each do |field_key, field_value|
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
