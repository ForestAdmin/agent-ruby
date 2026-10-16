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

          sort = QueryStringParser.parse_sort(context.collection, args)
          filter = build_context_filter(context.collection, args, context.permissions, context.caller, sort: sort)
                   .override(page: QueryStringParser.parse_pagination(args))

          projection = redacted_projection_with_pks(context, context.collection, args)
          records = context.collection.list(context.caller, filter, projection)

          {
            name: args[:params]['collection_name'],
            content: JSONAPI::Serializer.serialize(
              records,
              class_name: context.collection.name,
              is_collection: true,
              serializer: Serializer::ForestSerializer,
              include: projection.relation_include_paths,
              meta: handle_search_decorator(args[:params]['search'], records, context.collection)
            )
          }
        end

        def handle_search_decorator(search_value, records, collection)
          decorator = { decorators: [] }
          unless search_value.nil?
            search_value = search_value.downcase
            records.each_with_index do |entry, index|
              decorator[:decorators][index] = { id: Utils::Id.pack_id(collection, entry), search: [] }
              # attributes method is defined on ActiveRecord::Base model
              attributes = entry.respond_to?(:attributes) ? entry.attributes : entry

              attributes.each do |field_key, field_value|
                if !field_value.is_a?(Array) && field_value.to_s.downcase.include?(search_value)
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
