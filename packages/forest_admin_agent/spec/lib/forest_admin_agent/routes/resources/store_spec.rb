require 'spec_helper'
require 'singleton'
require 'ostruct'

module ForestAdminAgent
  module Routes
    module Resources
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminDatasourceToolkit::Schema
      describe Store do
        include_context 'with caller'
        subject(:store) { described_class.new }
        let(:args) do
          {
            headers: { 'HTTP_AUTHORIZATION' => bearer },
            params: {
              'collection_name' => 'book',
              'timezone' => 'Europe/Paris'
            }
          }
        end
        let(:permissions) { instance_double(ForestAdminAgent::Services::Permissions) }

        before do
          allow(ForestAdminAgent::Services::Permissions).to receive(:new).and_return(permissions)
          allow(permissions).to receive(:can?).and_return(true)
        end

        it 'adds the route forest_store' do
          store.setup_routes
          expect(store.routes.include?('forest_store')).to be true
          expect(store.routes.length).to eq 1
        end

        describe 'simple case' do
          before do
            book_class = Struct.new(:id, :title, :published_at, :price) do
              def respond_to?(arg)
                return false if arg == :each

                super
              end
            end
            stub_const('Book', book_class)
            allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)
          end

          it 'call create and return an serialized content' do
            attributes = {
              'title' => 'Harry potter and the goblet of fire',
              'published_at' => '2000-07-07T21:00:00.000Z',
              'price' => 6.75
            }
            book = { 'id' => 1 }.merge(attributes)

            datasource = Datasource.new
            collection = build_collection(
              name: 'book',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(
                    column_type: 'Number',
                    is_primary_key: true,
                    filter_operators: [Operators::IN, Operators::EQUAL]
                  ),
                  'title' => ColumnSchema.new(column_type: 'String'),
                  'published_at' => ColumnSchema.new(column_type: 'Date'),
                  'price' => ColumnSchema.new(column_type: 'Number')
                }
              },
              create: book,
              list: [book]
            )

            datasource.add_collection(collection)
            ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(datasource)
            ForestAdminAgent::Builder::AgentFactory.instance.build
            args[:params][:data] = { attributes: attributes, type: 'books' }

            result = store.handle_request(args)
            expect(collection).to have_received(:create) do |caller, data|
              expect(caller).to be_instance_of(Components::Caller)
              expect(data).to eq(attributes)
            end
            expect(result[:name]).to eq('book')
            expect(result[:content]).to eq(
              'data' =>
                {
                  'type' => 'book',
                  'id' => '1',
                  'attributes' => {
                    'id' => 1,
                    'title' => 'Harry potter and the goblet of fire',
                    'published_at' => '2000-07-07T21:00:00.000Z',
                    'price' => 6.75
                  },
                  'links' => { 'self' => '/forest/book/1' }
                }
            )
          end

          it 'includes null attributes in the returned result' do
            attributes = {
              'title' => 'Harry potter and the goblet of fire',
              'published_at' => nil,
              'price' => nil
            }
            book = { 'id' => 1 }.merge(attributes)

            datasource = Datasource.new
            collection = build_collection(
              name: 'book',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(
                    column_type: 'Number',
                    is_primary_key: true,
                    filter_operators: [Operators::IN, Operators::EQUAL]
                  ),
                  'title' => ColumnSchema.new(column_type: 'String'),
                  'published_at' => ColumnSchema.new(column_type: 'Date'),
                  'price' => ColumnSchema.new(column_type: 'Number')
                }
              },
              create: book,
              list: [book]
            )

            datasource.add_collection(collection)
            ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(datasource)
            ForestAdminAgent::Builder::AgentFactory.instance.build
            args[:params][:data] = { attributes: attributes, type: 'books' }

            result = store.handle_request(args)
            expect(collection).to have_received(:create) do |caller, data|
              expect(caller).to be_instance_of(Components::Caller)
              expect(data).to eq(attributes)
            end
            expect(result[:name]).to eq('book')
            expect(result[:content]).to eq(
              'data' =>
                {
                  'type' => 'book',
                  'id' => '1',
                  'attributes' => {
                    'id' => 1,
                    'title' => 'Harry potter and the goblet of fire',
                    'published_at' => nil,
                    'price' => nil
                  },
                  'links' => { 'self' => '/forest/book/1' }
                }
            )
          end
        end

        describe 'with relation' do
          before do
            @datasource = Datasource.new
            collection_person = build_collection(
              name: 'person',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(
                    column_type: 'Number',
                    is_primary_key: true,
                    filter_operators: [Operators::IN, Operators::EQUAL]
                  ),
                  'name' => ColumnSchema.new(column_type: 'String'),
                  'passport' => Relations::OneToOneSchema.new(
                    origin_key: 'person_id',
                    origin_key_target: 'id',
                    foreign_collection: 'passport'
                  )
                }
              }
            )

            collection_passport = build_collection(
              name: 'passport',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(
                    column_type: 'Number',
                    is_primary_key: true,
                    filter_operators: [Operators::IN, Operators::EQUAL]
                  ),
                  'person_id' => ColumnSchema.new(column_type: 'Number'),
                  'person' => Relations::ManyToOneSchema.new(
                    foreign_key: 'person_id',
                    foreign_key_target: 'id',
                    foreign_collection: 'passport'
                  )
                }
              }
            )
            @datasource.add_collection(collection_person)
            @datasource.add_collection(collection_passport)
            allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)
            ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(@datasource)
            ForestAdminAgent::Builder::AgentFactory.instance.build
          end

          describe 'with one to one relation' do
            it 'call create and return an serialized content' do
              args[:params][:data] = {
                attributes: { 'name' => 'john' },
                relationships: { 'passport' => { 'data' => { 'type' => 'passports', 'id' => 1 } } },
                type: 'persons'
              }
              args[:params]['collection_name'] = 'person'
              allow(@datasource.get_collection('person')).to receive_messages(
                create: { 'id' => 1, 'name' => 'john' },
                list: [{ 'id' => 1, 'name' => 'john' }]
              )
              allow(@datasource.get_collection('passport')).to receive(:update).and_return(
                { 'id' => 1, 'person_id' => 1 }
              )

              result = store.handle_request(args)
              expect(@datasource.get_collection('person')).to have_received(:create) do |caller, data|
                expect(caller).to be_instance_of(Components::Caller)
                expect(data).to eq({ 'name' => 'john' })
              end
              expect(@datasource.get_collection('passport')).to have_received(:update) do |caller, filter, data|
                expect(caller).to be_instance_of(Components::Caller)
                expect(data).to eq({ 'person_id' => 1 })
                expect(filter.condition_tree.to_h).to eq({ field: 'id', operator: Operators::EQUAL, value: 1 })
              end
              expect(result[:name]).to eq('person')
              expect(result[:content]).to eq(
                'data' =>
                  {
                    'type' => 'person',
                    'id' => '1',
                    'attributes' => { 'id' => 1, 'name' => 'john' },
                    'links' => { 'self' => '/forest/person/1' },
                    'relationships' => {
                      'passport' => {
                        'links' => { 'related' => { 'href' => '/forest/person/1/relationships/passport' } }
                      }
                    }
                  }
              )
            end
          end

          describe 'with many to one relation' do
            it 'call create and return an serialized content' do
              args[:params][:data] = {
                attributes: {},
                relationships: { 'person' => { 'data' => { 'type' => 'person', 'id' => 1 } } },
                type: 'persons'
              }
              args[:params]['collection_name'] = 'passport'
              allow(@datasource.get_collection('passport')).to receive_messages(
                create: { 'id' => 1, 'person_id' => 1 },
                list: [{ 'id' => 1, 'person_id' => 1 }]
              )

              result = store.handle_request(args)
              expect(@datasource.get_collection('passport')).to have_received(:create) do |caller, data|
                expect(caller).to be_instance_of(Components::Caller)
                expect(data).to eq({ 'person_id' => 1 })
              end
              expect(result[:name]).to eq('passport')
              expect(result[:content]).to eq(
                'data' =>
                  {
                    'type' => 'passport',
                    'id' => '1',
                    'attributes' => { 'id' => 1, 'person_id' => 1 },
                    'links' => { 'self' => '/forest/passport/1' },
                    'relationships' => {
                      'person' => {
                        'links' => {
                          'related' => {
                            'href' => '/forest/passport/1/relationships/person'
                          }
                        }
                      }
                    }
                  }
              )
            end
          end

          describe 'with polymorphic many to one relation' do
            it 'call create with polymorphic foreign key and type' do
              collection_company = build_collection(
                name: 'company',
                schema: {
                  fields: {
                    'id' => ColumnSchema.new(
                      column_type: 'Number',
                      is_primary_key: true,
                      filter_operators: [Operators::IN, Operators::EQUAL]
                    ),
                    'name' => ColumnSchema.new(column_type: 'String')
                  }
                }
              )

              collection_member = build_collection(
                name: 'member',
                schema: {
                  fields: {
                    'id' => ColumnSchema.new(
                      column_type: 'Number',
                      is_primary_key: true,
                      filter_operators: [Operators::IN, Operators::EQUAL]
                    ),
                    'memberable_id' => ColumnSchema.new(column_type: 'Number'),
                    'memberable_type' => ColumnSchema.new(column_type: 'String'),
                    'memberable' => Relations::PolymorphicManyToOneSchema.new(
                      foreign_collections: ['company'],
                      foreign_key: 'memberable_id',
                      foreign_key_type_field: 'memberable_type',
                      foreign_key_targets: { 'company' => 'id' }
                    )
                  }
                }
              )

              @datasource.add_collection(collection_company)
              @datasource.add_collection(collection_member)

              args[:params][:data] = {
                attributes: {},
                relationships: { 'memberable' => { 'data' => { 'type' => 'Company', 'id' => 3 } } },
                type: 'Member'
              }
              args[:params]['collection_name'] = 'member'
              allow(@datasource.get_collection('member')).to receive_messages(
                create: { 'id' => 1, 'memberable_id' => 3, 'memberable_type' => 'Company' },
                list: [{ 'id' => 1, 'memberable_id' => 3, 'memberable_type' => 'Company' }]
              )

              result = store.handle_request(args)
              expect(@datasource.get_collection('member')).to have_received(:create) do |caller, data|
                expect(caller).to be_instance_of(Components::Caller)
                expect(data).to eq({ 'memberable_id' => 3, 'memberable_type' => 'Company' })
              end
              expect(result[:name]).to eq('member')
            end
          end
        end
      end
    end
  end
end
