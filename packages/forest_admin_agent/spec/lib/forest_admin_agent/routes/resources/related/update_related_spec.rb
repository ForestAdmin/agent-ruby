require 'spec_helper'
require 'shared/caller'

module ForestAdminAgent
  module Routes
    module Resources
      module Related
        include ForestAdminDatasourceToolkit
        include ForestAdminDatasourceToolkit::Schema
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
        describe UpdateRelated do
          include_context 'with caller'
          subject(:update) { described_class.new }

          let(:permissions) { instance_double(ForestAdminAgent::Services::Permissions) }

          before do
            datasource = Datasource.new
            collection_user = Collection.new(datasource, 'user')
            collection_user.add_fields(
              {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true,
                                         filter_operators: [Operators::IN, Operators::EQUAL]),
                'name' => ColumnSchema.new(column_type: 'String'),
                'book' => Relations::OneToOneSchema.new(
                  origin_key: 'author_id',
                  origin_key_target: 'id',
                  foreign_collection: 'book'
                ),
                'address' => Relations::PolymorphicOneToOneSchema.new(
                  origin_key: 'addressable_id',
                  foreign_collection: 'address',
                  origin_key_target: 'id',
                  origin_type_field: 'addressable_type',
                  origin_type_value: 'user'
                )
              }
            )

            collection_book = ForestAdminDatasourceToolkit::Collection.new(datasource, 'book')
            collection_book.add_fields(
              {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true,
                                         filter_operators: [Operators::IN, Operators::EQUAL]),
                'author_id' => ColumnSchema.new(column_type: 'Number'),
                'author' => Relations::ManyToOneSchema.new(
                  foreign_key: 'author_id',
                  foreign_key_target: 'id',
                  foreign_collection: 'user'
                )
              }
            )

            collection_address = collection_build(
              name: 'address',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true,
                                           filter_operators: [Operators::IN, Operators::EQUAL]),
                  'location' => ColumnSchema.new(column_type: 'String'),
                  'addressable_id' => ColumnSchema.new(column_type: 'Number'),
                  'addressable_type' => ColumnSchema.new(column_type: 'String'),
                  'addressable' => Relations::PolymorphicManyToOneSchema.new(
                    foreign_key_type_field: 'addressable_type',
                    foreign_collections: ['user'],
                    foreign_key_targets: { 'user' => 'id' },
                    foreign_key: 'addressable_id'
                  )
                }
              }
            )

            allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)
            datasource.add_collection(collection_user)
            datasource.add_collection(collection_book)
            datasource.add_collection(collection_address)
            ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(datasource)
            ForestAdminAgent::Builder::AgentFactory.instance.build
            @datasource = ForestAdminAgent::Facades::Container.datasource

            allow(ForestAdminAgent::Services::Permissions).to receive(:new).and_return(permissions)
            allow(permissions).to receive_messages(can?: true, get_scope: nil)
          end

          it 'adds the route forest_related_update' do
            update.setup_routes
            expect(update.routes.include?('forest_related_update')).to be true
            expect(update.routes.length).to eq 1
          end

          context 'when handle_request is called' do
            let(:args) do
              {
                headers: { 'HTTP_AUTHORIZATION' => bearer },
                params: {
                  'timezone' => 'Europe/Paris'
                }
              }
            end

            before do
              user_class = Struct.new(:id, :name, :book)
              stub_const('User', user_class)
              book_class = Struct.new(:id, :author)
              stub_const('Book', book_class)
            end

            it 'call handle_request on a many_to_one relation' do
              allow(@datasource.get_collection('book')).to receive(:update).and_return(true)

              args[:params]['collection_name'] = 'book'
              args[:params]['relation_name'] = 'author'
              args[:params]['data'] = { 'id' => 1 }
              args[:params]['id'] = 1

              result = update.handle_request(args)

              expect(@datasource.get_collection('book')).to have_received(:update) do |caller, filter, data|
                expect(caller).to be_instance_of(Components::Caller)
                expect(filter).to have_attributes(
                  condition_tree: have_attributes(field: 'id', operator: Operators::EQUAL, value: 1),
                  page: nil,
                  search: nil,
                  search_extended: nil,
                  segment: nil,
                  sort: nil
                )
                expect(data).to eq({ 'author_id' => 1 })
              end
              expect(result).to eq({ content: nil, status: 204 })
            end

            it 'call handle_request on a polymorphic_many_to_one relation' do
              allow(@datasource.get_collection('address')).to receive(:update).and_return(true)

              args[:params]['collection_name'] = 'address'
              args[:params]['relation_name'] = 'addressable'
              args[:params]['data'] = { 'id' => 1, 'type' => 'user' }
              args[:params]['id'] = 1

              result = update.handle_request(args)

              expect(@datasource.get_collection('address')).to have_received(:update) do |caller, filter, data|
                expect(caller).to be_instance_of(Components::Caller)
                expect(filter).to have_attributes(
                  condition_tree: have_attributes(field: 'id', operator: Operators::EQUAL, value: 1),
                  page: nil,
                  search: nil,
                  search_extended: nil,
                  segment: nil,
                  sort: nil
                )
                expect(data).to eq({ 'addressable_id' => 1, 'addressable_type' => 'user' })
              end
              expect(result).to eq({ content: nil, status: 204 })
            end

            it 'call handle_request on a one_to_one relation' do
              allow(@datasource.get_collection('book')).to receive_messages(aggregate: [{ 'value' => 1 }], update: true)

              args[:params]['collection_name'] = 'user'
              args[:params]['relation_name'] = 'book'
              args[:params]['data'] = { 'id' => 1 }
              args[:params]['id'] = 1

              result = update.handle_request(args)

              parameters = [
                [
                  Components::Caller,
                  {
                    condition_tree: have_attributes(
                      aggregator: 'And',
                      conditions: [
                        have_attributes(field: 'author_id', operator: Operators::EQUAL, value: 1),
                        have_attributes(field: 'id', operator: Operators::NOT_EQUAL, value: 1)
                      ]
                    ),
                    page: nil,
                    search: nil,
                    search_extended: nil,
                    segment: nil,
                    sort: nil
                  },
                  { 'author_id' => nil }
                ],
                [
                  Components::Caller,
                  {
                    condition_tree: have_attributes(field: 'id', operator: Operators::EQUAL, value: 1),
                    page: nil,
                    search: nil,
                    search_extended: nil,
                    segment: nil,
                    sort: nil
                  },
                  { 'author_id' => 1 }
                ]
              ]

              expect(@datasource.get_collection('book')).to have_received(:update)
                .exactly(2).times do |caller, filter, data|
                parameter = parameters.shift
                expect(caller).to be_instance_of(parameter[0])
                expect(filter).to have_attributes(parameter[1])
                expect(data).to eq(parameter[2])
              end
              expect(result).to eq({ content: nil, status: 204 })
            end

            it 'call handle_request on a polymorphic_one_to_one relation' do
              allow(@datasource.get_collection('address')).to receive_messages(aggregate: [{ 'value' => 1 }], update: true)

              args[:params]['collection_name'] = 'user'
              args[:params]['relation_name'] = 'address'
              args[:params]['data'] = { 'id' => 1, 'type' => 'user ' }
              args[:params]['id'] = 1

              result = update.handle_request(args)

              parameters = [
                [
                  Components::Caller,
                  {
                    condition_tree: have_attributes(
                      aggregator: 'And',
                      conditions: [
                        have_attributes(field: 'addressable_id', operator: Operators::EQUAL, value: 1),
                        have_attributes(field: 'addressable_type', operator: Operators::EQUAL, value: 'user'),
                        have_attributes(field: 'id', operator: Operators::NOT_EQUAL, value: 1)
                      ]
                    ),
                    page: nil,
                    search: nil,
                    search_extended: nil,
                    segment: nil,
                    sort: nil
                  },
                  { 'addressable_id' => nil, 'addressable_type' => nil }
                ],
                [
                  Components::Caller,
                  {
                    condition_tree: have_attributes(field: 'id', operator: Operators::EQUAL, value: 1),
                    page: nil,
                    search: nil,
                    search_extended: nil,
                    segment: nil,
                    sort: nil
                  },
                  { 'addressable_id' => 1, 'addressable_type' => 'user' }
                ]
              ]

              expect(@datasource.get_collection('address')).to have_received(:update)
                .exactly(2).times do |caller, filter, data|
                parameter = parameters.shift
                expect(caller).to be_instance_of(parameter[0])
                expect(filter).to have_attributes(parameter[1])
                expect(data).to eq(parameter[2])
              end
              expect(result).to eq({ content: nil, status: 204 })
            end
          end
        end
      end
    end
  end
end
