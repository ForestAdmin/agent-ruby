require 'spec_helper'
require 'singleton'
require 'ostruct'

module ForestAdminAgent
  module Routes
    module Resources
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminDatasourceToolkit::Schema
      describe Delete do
        include_context 'with caller'
        subject(:delete) { described_class.new }
        let(:args) do
          {
            headers: { 'HTTP_AUTHORIZATION' => bearer },
            params: params
          }
        end
        let(:permissions) { instance_double(ForestAdminAgent::Services::Permissions) }

        before do
          allow(ForestAdminAgent::Services::Permissions).to receive(:new).and_return(permissions)
          allow(permissions).to receive_messages(can?: true, get_scope: nil)
        end

        it 'adds the route forest_store' do
          delete.setup_routes
          expect(delete.routes.include?('forest_delete')).to be true
          expect(delete.routes.include?('forest_delete_bulk')).to be true
          expect(delete.routes.length).to eq 2
        end

        describe 'handle requests' do
          before do
            user_class = Struct.new(:id, :first_name, :last_name) do
              def respond_to?(arg)
                return false if arg == :each

                super
              end
            end
            stub_const('User', user_class)

            datasource = Datasource.new

            collection = build_collection(
              name: 'user',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(
                    column_type: 'Number',
                    is_primary_key: true,
                    filter_operators: [Operators::IN, Operators::EQUAL]
                  ),
                  'first_name' => ColumnSchema.new(column_type: 'String'),
                  'last_name' => ColumnSchema.new(column_type: 'String')
                }
              },
              delete: true
            )

            allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)
            datasource.add_collection(collection)
            ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(datasource)
            ForestAdminAgent::Builder::AgentFactory.instance.build

            @datasource = ForestAdminAgent::Facades::Container.datasource
            allow(@datasource.get_collection('user')).to receive(:delete)
          end

          context 'with simple request' do
            let(:params) do
              {
                'collection_name' => 'user',
                'timezone' => 'Europe/Paris',
                'id' => 1
              }
            end

            it 'returns an empty content and a 204 status' do
              result = delete.handle_request(args)

              expect(result[:content]).to be_nil
              expect(result[:status]).to eq 204
            end

            it 'call delete function with expected args' do
              delete.handle_request(args)

              expect(@datasource.get_collection('user')).to have_received(:delete) do |caller, filter|
                expect(caller).to be_instance_of(Components::Caller)
                expect(filter.condition_tree.to_h).to eq(field: 'id', operator: Operators::EQUAL, value: 1)
              end
            end
          end

          context 'with bulk request' do
            let(:params) do
              {
                'collection_name' => 'user',
                'timezone' => 'Europe/Paris',
                data: {
                  attributes: {
                    ids: %w[1 2 3],
                    collection_name: 'Car',
                    parent_collection_name: nil,
                    parent_collection_id: nil,
                    parent_association_name: nil,
                    all_records: false,
                    all_records_subset_query: {
                      'fields[Car]' => 'id,model,brand',
                      'page[number]' => 1,
                      'page[size]' => 15
                    },
                    all_records_ids_excluded: [],
                    smart_action_id: nil
                  },
                  type: 'action-requests'
                }
              }
            end

            it 'returns an empty content and a 204 status' do
              result = delete.handle_request_bulk(args)

              expect(result[:content]).to be_nil
              expect(result[:status]).to eq 204
            end

            it 'call delete function with filters for only ids selected' do
              delete.handle_request_bulk(args)

              expect(@datasource.get_collection('user')).to have_received(:delete) do |caller, filter|
                expect(caller).to be_instance_of(Components::Caller)
                expect(filter.condition_tree.to_h).to eq(field: 'id', operator: Operators::IN, value: [1, 2, 3])
              end
            end

            it 'call delete function with filters for only ids no selected' do
              args[:params][:data][:attributes][:all_records] = true
              args[:params][:data][:attributes][:all_records_ids_excluded] = %w[1 2 3]
              delete.handle_request_bulk(args)

              expect(@datasource.get_collection('user')).to have_received(:delete) do |caller, filter|
                expect(caller).to be_instance_of(Components::Caller)
                expect(filter.condition_tree.to_h).to eq(field: 'id', operator: Operators::NOT_IN, value: [1, 2, 3])
              end
            end
          end

          context 'with polymorphic relations' do
            before do
              cache = FileCache.new('app', 'tmp/cache/forest_admin')
              cache.clear

              agent_factory = ForestAdminAgent::Builder::AgentFactory.instance
              agent_factory.setup(
                {
                  auth_secret: 'cba803d01a4d43b55010cab41fa1ea1f1f51a95e',
                  env_secret: '89719c6d8e2e2de2694c2f220fe2dbf02d5289487364daf1e4c6b13733ed0cdb',
                  is_production: false,
                  cache_dir: 'tmp/cache/forest_admin',
                  schema_path: File.join('tmp', '.forestadmin-schema.json'),
                  forest_server_url: 'https://api.development.forestadmin.com',
                  debug: true,
                  prefix: 'forest',
                  customize_error_message: nil,
                  append_schema_path: nil
                }
              )

              address_class = Struct.new(:id, :street, :addressable_id, :addressable_type)
              stub_const('Address', address_class)

              datasource = Datasource.new

              user_collection = build_collection(
                name: 'user',
                schema: {
                  fields: {
                    'id' => ColumnSchema.new(
                      column_type: 'Number',
                      is_primary_key: true,
                      filter_operators: [Operators::IN, Operators::EQUAL]
                    ),
                    'first_name' => ColumnSchema.new(column_type: 'String'),
                    'last_name' => ColumnSchema.new(column_type: 'String'),
                    'address' => Relations::PolymorphicOneToOneSchema.new(
                      foreign_collection: 'address',
                      origin_key: 'addressable_id',
                      origin_key_target: 'id',
                      origin_type_field: 'addressable_type',
                      origin_type_value: 'User'
                    )
                  }
                },
                delete: true
              )

              address_collection = build_collection(
                name: 'address',
                schema: {
                  fields: {
                    'id' => ColumnSchema.new(
                      column_type: 'Number',
                      is_primary_key: true,
                      filter_operators: [Operators::IN, Operators::EQUAL]
                    ),
                    'street' => ColumnSchema.new(column_type: 'String'),
                    'addressable_id' => ColumnSchema.new(column_type: 'Number'),
                    'addressable_type' => ColumnSchema.new(column_type: 'String')
                  }
                },
                update: true
              )

              allow(agent_factory).to receive(:send_schema).and_return(nil)
              datasource.add_collection(user_collection)
              datasource.add_collection(address_collection)
              agent_factory.add_datasource(datasource)
              agent_factory.build

              @datasource = ForestAdminAgent::Facades::Container.datasource
              allow(@datasource.get_collection('user')).to receive(:delete)
              allow(@datasource.get_collection('address')).to receive(:update)
            end

            describe 'polymorphic relation cleanup with single record' do
              let(:params) do
                {
                  'collection_name' => 'user',
                  'timezone' => 'Europe/Paris',
                  'id' => 42
                }
              end

              it 'handles single record deletion with hash format primary keys' do
                delete.handle_request(args)

                expect(@datasource.get_collection('address')).to have_received(:update) do |caller, filter, patch|
                  expect(caller).to be_instance_of(Components::Caller)

                  condition_tree = filter.condition_tree
                  expect(condition_tree).to be_a(Nodes::ConditionTreeBranch)
                  expect(condition_tree.aggregator).to eq('And')

                  in_condition = condition_tree.conditions.find { |c| c.is_a?(Nodes::ConditionTreeLeaf) && c.field == 'addressable_id' }
                  expect(in_condition).not_to be_nil
                  expect(in_condition.operator).to eq(Operators::IN)
                  expect(in_condition.value).to eq([42])

                  expect(patch).to eq({ 'addressable_id' => nil, 'addressable_type' => nil })
                end
              end
            end
          end

          context 'with composite primary keys and polymorphic relations' do
            before do
              cache = FileCache.new('app', 'tmp/cache/forest_admin')
              cache.clear

              agent_factory = ForestAdminAgent::Builder::AgentFactory.instance
              agent_factory.setup(
                {
                  auth_secret: 'cba803d01a4d43b55010cab41fa1ea1f1f51a95e',
                  env_secret: '89719c6d8e2e2de2694c2f220fe2dbf02d5289487364daf1e4c6b13733ed0cdb',
                  is_production: false,
                  cache_dir: 'tmp/cache/forest_admin',
                  schema_path: File.join('tmp', '.forestadmin-schema.json'),
                  forest_server_url: 'https://api.development.forestadmin.com',
                  debug: true,
                  prefix: 'forest',
                  customize_error_message: nil,
                  append_schema_path: nil
                }
              )

              composite_class = Struct.new(:key1, :key2, :name)
              address_class = Struct.new(:id, :street, :owner_key1, :owner_type)
              stub_const('CompositeModel', composite_class)
              stub_const('CompositeAddress', address_class)

              datasource = Datasource.new

              composite_collection = build_collection(
                name: 'composite_model',
                schema: {
                  fields: {
                    'key1' => ColumnSchema.new(
                      column_type: 'String',
                      is_primary_key: true,
                      filter_operators: [Operators::IN, Operators::EQUAL]
                    ),
                    'key2' => ColumnSchema.new(
                      column_type: 'Number',
                      is_primary_key: true,
                      filter_operators: [Operators::IN, Operators::EQUAL]
                    ),
                    'name' => ColumnSchema.new(column_type: 'String'),
                    'address' => Relations::PolymorphicOneToManySchema.new(
                      foreign_collection: 'composite_address',
                      origin_key: 'owner_key1',
                      origin_key_target: 'key1',
                      origin_type_field: 'owner_type',
                      origin_type_value: 'CompositeModel'
                    )
                  }
                },
                delete: true
              )

              address_collection = build_collection(
                name: 'composite_address',
                schema: {
                  fields: {
                    'id' => ColumnSchema.new(
                      column_type: 'Number',
                      is_primary_key: true,
                      filter_operators: [Operators::IN, Operators::EQUAL]
                    ),
                    'street' => ColumnSchema.new(column_type: 'String'),
                    'owner_key1' => ColumnSchema.new(column_type: 'String'),
                    'owner_type' => ColumnSchema.new(column_type: 'String')
                  }
                },
                update: true
              )

              allow(agent_factory).to receive(:send_schema).and_return(nil)
              datasource.add_collection(composite_collection)
              datasource.add_collection(address_collection)
              agent_factory.add_datasource(datasource)
              agent_factory.build

              @datasource = ForestAdminAgent::Facades::Container.datasource
              allow(@datasource.get_collection('composite_model')).to receive(:delete)
              allow(@datasource.get_collection('composite_address')).to receive(:update)
            end

            describe 'extracts correct field from composite primary keys' do
              let(:params) do
                {
                  'collection_name' => 'composite_model',
                  'timezone' => 'Europe/Paris',
                  data: {
                    attributes: {
                      ids: ['abc|1', 'def|2', 'ghi|3'],
                      collection_name: 'CompositeModel',
                      parent_collection_name: nil,
                      parent_collection_id: nil,
                      parent_association_name: nil,
                      all_records: false,
                      all_records_subset_query: {},
                      all_records_ids_excluded: [],
                      smart_action_id: nil
                    },
                    type: 'action-requests'
                  }
                }
              end

              it 'extracts the correct primary key field for origin_key_target from composite keys' do
                delete.handle_request_bulk(args)

                expect(@datasource.get_collection('composite_address')).to have_received(:update) do |caller, filter, patch|
                  expect(caller).to be_instance_of(Components::Caller)

                  condition_tree = filter.condition_tree
                  expect(condition_tree).to be_a(Nodes::ConditionTreeBranch)

                  in_condition = condition_tree.conditions.find { |c| c.is_a?(Nodes::ConditionTreeLeaf) && c.field == 'owner_key1' }
                  expect(in_condition).not_to be_nil
                  expect(in_condition.operator).to eq(Operators::IN)
                  expect(in_condition.value).to eq(%w[abc def ghi])

                  expect(patch).to eq({ 'owner_key1' => nil, 'owner_type' => nil })
                end
              end
            end
          end
        end
      end
    end
  end
end
