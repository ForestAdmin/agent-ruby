module ForestAdminAgent
  module Routes
    module Resources
      class List < AbstractRoute
        include ForestAdminAgent::Builder
        def setup_routes
          add_route('forest_list', 'get', '/:collection_name', ->(args) { handle_request(args) })

          self
        end

        def handle_request(args = {})
          record = [
            {
              'id' => '1',
              'first_name' => 'aaa',
              'last_name' => 'bbb',
              'category' => {
                'id' => '1',
                'name' => 'category 1'
              },
              'orders' => [
                {
                  'id' => '1',
                  'name' => 'order 1'
                },
                {
                  'id' => '2',
                  'name' => 'order 2'
                }
              ]
            },
            {
              'id' => '2',
              'first_name' => 'toto',
              'last_name' => 'tata',
              'category' => {
                'id' => '1',
                'name' => 'category 1'
              },
              'orders' => [
                {
                  'id' => '3',
                  'name' => 'order 3'
                },
                {
                  'id' => '4',
                  'name' => 'order 4'
                }
              ]
            }
          ]

          data = record.is_a?(Array) ? record.map { |record| OpenStruct.new(record) } : OpenStruct.new(record)
          JSONAPI::Serializer.serialize(
            data,
            is_collection: data.is_a?(Array),
            serializer: Serializer::ForestSerializer,
            context: args['collection_name']
          )
        end
      end
    end
  end
end
