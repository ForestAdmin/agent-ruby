require 'jsonapi-serializers'

module ForestAdminAgent
  module Routes
    module Resources
      class List < AbstractAuthenticatedRoute
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
        include ForestAdminAgent::Utils
        include ForestAdminAgent::Routes::QueryHandler

        def setup_routes
          add_route('forest_list', 'get', '/:collection_name', ->(args) { handle_request(args) })

          self
        end

        def handle_request(args = {})
          context = build(args)
          context.permissions.can?(:browse, context.collection)

          filter = ForestAdminDatasourceToolkit::Components::Query::Filter.new(
            condition_tree: ConditionTreeFactory.intersect(
              [
                context.permissions.get_scope(context.collection),
                QueryStringParser.parse_condition_tree(context.collection, args),
                parse_query_segment(context.collection, args, context.permissions, context.caller)
              ]
            ),
            page: QueryStringParser.parse_pagination(args),
            search: QueryStringParser.parse_search(context.collection, args),
            search_extended: QueryStringParser.parse_search_extended(args),
            sort: QueryStringParser.parse_sort(context.collection, args),
            segment: QueryStringParser.parse_segment(context.collection, args)
          )

          projection = QueryStringParser.parse_projection_with_pks(context.collection, args)
          records = context.collection.list(context.caller, filter, projection)

          {
            name: args[:params]['collection_name'],
            content: JSONAPI::Serializer.serialize(
              records,
              class_name: context.collection.name,
              is_collection: true,
              serializer: Serializer::ForestSerializer,
              include: projection.relations(only_keys: true),
              meta: handle_search_decorator(args[:params]['search'], records, context.collection)
            )
          }
        end

        def handle_search_decorator(search_value, records, collection)
          decorator = { decorators: [] }
          unless search_value.nil?
            records.each_with_index do |entry, index|
              decorator[:decorators][index] = { id: Utils::Id.pack_id(collection, entry), search: [] }
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
