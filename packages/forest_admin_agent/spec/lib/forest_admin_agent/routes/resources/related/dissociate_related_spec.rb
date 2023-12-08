require 'spec_helper'
require 'shared/caller'

module ForestAdminAgent
  module Routes
    module Resources
      module Related
        include ForestAdminDatasourceToolkit
        include ForestAdminDatasourceToolkit::Schema
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
        describe DissociateRelated do
          include_context 'with caller'
          subject(:dissociate) { described_class.new }

          let(:datasource) { Datasource.new }
          let(:permissions) { instance_double(ForestAdminAgent::Services::Permissions) }

          before do
            collection_user = Collection.new(datasource, 'user')
            collection_user.add_fields(
              {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true,
                                         filter_operators: [Operators::IN, Operators::EQUAL]),
                'name' => ColumnSchema.new(column_type: 'String'),
                'addresses' => Relations::ManyToManySchema.new(
                  foreign_key: 'address_id',
                  foreign_collection: 'address',
                  foreign_key_target: 'id',
                  through_collection: 'address_user',
                  origin_key: 'user_id',
                  origin_key_target: 'id'
                ),
                'address_users' => Relations::OneToManySchema.new(
                  origin_key: 'user_id',
                  origin_key_target: 'id',
                  foreign_collection: 'address_user'
                )
              }
            )

            collection_address_user = Collection.new(datasource, 'address_user')
            collection_address_user.add_fields(
              {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true,
                                         filter_operators: [Operators::IN, Operators::EQUAL]),
                'address_id' => Relations::ManyToOneSchema.new(
                  foreign_key: 'address_id',
                  foreign_collection: 'address',
                  foreign_key_target: 'id'
                ),
                'user_id' => Relations::ManyToOneSchema.new(
                  foreign_key: 'user_id',
                  foreign_collection: 'user',
                  foreign_key_target: 'id'
                )
              }
            )

            collection_address = Collection.new(datasource, 'address')
            collection_address.add_fields(
              {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true,
                                         filter_operators: [Operators::IN, Operators::EQUAL]),
                'location' => ColumnSchema.new(column_type: 'String')
              }
            )

            allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)
            datasource.add_collection(collection_user)
            datasource.add_collection(collection_address_user)
            datasource.add_collection(collection_address)
            ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(datasource)
            ForestAdminAgent::Builder::AgentFactory.instance.build

            allow(ForestAdminAgent::Services::Permissions).to receive(:new).and_return(permissions)
            allow(permissions).to receive_messages(can?: true, get_scope: Nodes::ConditionTreeBranch.new('Or', []))
          end

          it 'adds the route forest_related_dissociate' do
            dissociate.setup_routes
            expect(dissociate.routes.include?('forest_related_dissociate')).to be true
            expect(dissociate.routes.length).to eq 1
          end

          context 'when handle_request is called' do
            let(:args) do
              {
                headers: { 'HTTP_AUTHORIZATION' => bearer },
                params: {
                  'collection_name' => 'user',
                  'timezone' => 'Europe/Paris'
                }
              }
            end

            before do
              user_class = Struct.new(:id, :name)
              stub_const('User', user_class)
              address_class = Struct.new(:id, :location)
              stub_const('Address', address_class)
              address_user_class = Struct.new(:id, :user_id, :address_id)
              stub_const('AddressUser', address_user_class)
            end

            it 'call dissociate_or_delete_one_to_many without deletion' do
              allow(datasource.collection('address_user')).to receive(:update).and_return(true)

              args[:params]['relation_name'] = 'address_users'
              args[:params]['data'] = [{ 'id' => 1 }]
              args[:params]['id'] = 1

              result = dissociate.handle_request(args)

              expect(datasource.collection('address_user')).to have_received(:update) do |caller, filter, data|
                expect(caller).to be_instance_of(Components::Caller)
                expect(filter).to have_attributes(
                  condition_tree: have_attributes(
                    aggregator: 'And',
                    conditions: [
                      have_attributes(aggregator: 'Or', conditions: []),
                      have_attributes(field: 'id', operator: Operators::EQUAL, value: 1),
                      have_attributes(field: 'user_id', operator: Operators::EQUAL, value: 1)
                    ]
                  ),
                  page: nil,
                  search: nil,
                  search_extended: nil,
                  segment: nil,
                  sort: nil
                )
                expect(data).to eq({ 'user_id' => nil })
              end

              expect(result).to eq({ content: nil, status: 204 })
            end

            it 'call dissociate_or_delete_one_to_many with deletion' do
              allow(datasource.collection('address_user')).to receive(:delete).and_return(true)
              allow(datasource.collection('address')).to receive(:delete).and_return(true)

              args[:params][:delete] = true
              args[:params]['relation_name'] = 'address_users'
              args[:params]['data'] = [{ 'id' => 1 }]
              args[:params]['id'] = 1

              result = dissociate.handle_request(args)

              expect(datasource.collection('address_user')).to have_received(:delete) do |caller, filter|
                expect(caller).to be_instance_of(Components::Caller)
                expect(filter).to have_attributes(
                  condition_tree: have_attributes(
                    aggregator: 'And',
                    conditions: [
                      have_attributes(aggregator: 'Or', conditions: []),
                      have_attributes(field: 'id', operator: Operators::EQUAL, value: 1),
                      have_attributes(field: 'user_id', operator: Operators::EQUAL, value: 1)
                    ]
                  ),
                  page: nil,
                  search: nil,
                  search_extended: nil,
                  segment: nil,
                  sort: nil
                )
              end

              expect(result).to eq({ content: nil, status: 204 })
            end

            it 'call dissociate_or_delete_one_to_many with deletion on multiple records' do
              allow(datasource.collection('address_user')).to receive(:delete).and_return(true)
              allow(datasource.collection('address')).to receive(:delete).and_return(true)

              args[:params][:delete] = true
              args[:params]['relation_name'] = 'address_users'
              args[:params]['data'] = {
                'attributes' =>
                  { 'ids' => [{ 'id' => '1', 'type' => 'address_user' }],
                    'all_records' => true,
                    'all_records_ids_excluded' => ['2'] }
              }
              args[:params]['id'] = 1

              result = dissociate.handle_request(args)

              expect(datasource.collection('address_user')).to have_received(:delete) do |caller, filter|
                expect(caller).to be_instance_of(Components::Caller)
                expect(filter).to have_attributes(
                  condition_tree: have_attributes(
                    aggregator: 'And',
                    conditions: [
                      have_attributes(aggregator: 'Or', conditions: []),
                      have_attributes(field: 'id', operator: Operators::NOT_EQUAL, value: 2),
                      have_attributes(field: 'user_id', operator: Operators::EQUAL, value: 1)
                    ]
                  ),
                  page: nil,
                  search: nil,
                  search_extended: nil,
                  segment: nil,
                  sort: nil
                )
              end
              expect(result).to eq({ content: nil, status: 204 })
            end

            it 'call dissociate_or_delete_one_to_many with deletion should throw when there is no ids' do
              allow(Utils::Id).to receive(:parse_selection_ids).and_return({ ids: [] })

              args[:params][:delete] = true
              args[:params]['relation_name'] = 'address_users'
              args[:params]['id'] = 1

              expect do
                dissociate.handle_request(args)
              end.to raise_error(
                ForestAdminDatasourceToolkit::Exceptions::ForestException,
                '🌳🌳🌳 Expected no empty id list'
              )
            end

            it 'call dissociate_or_delete_many_to_many without deletion' do
              allow(datasource.collection('address_user')).to receive_messages(list: [AddressUser.new(1, 1, 1)],
                                                                               delete: true)

              args[:params]['relation_name'] = 'addresses'
              args[:params]['data'] = [{ 'id' => 1 }]
              args[:params]['id'] = 1

              result = dissociate.handle_request(args)

              expect(datasource.collection('address_user')).to have_received(:delete) do |caller, filter|
                expect(caller).to be_instance_of(Components::Caller)
                expect(filter).to have_attributes(
                  condition_tree: have_attributes(
                    aggregator: 'And',
                    conditions: [
                      have_attributes(field: 'user_id', operator: Operators::EQUAL, value: 1),
                      have_attributes(aggregator: 'Or', conditions: []),
                      have_attributes(field: 'address_id:id', operator: Operators::EQUAL, value: 1)
                    ]
                  ),
                  page: nil,
                  search: nil,
                  search_extended: nil,
                  segment: nil,
                  sort: nil
                )
              end

              expect(result).to eq({ content: nil, status: 204 })
            end

            it 'call dissociate_or_delete_many_to_many with deletion' do
              allow(datasource.collection('address_user')).to receive_messages(list: [AddressUser.new(1, 1, 1)],
                                                                               delete: true)
              allow(datasource.collection('address')).to receive(:delete).and_return(true)

              args[:params][:delete] = true
              args[:params]['relation_name'] = 'addresses'
              args[:params]['data'] = [{ 'id' => 1 }]
              args[:params]['id'] = 1

              result = dissociate.handle_request(args)

              expect(datasource.collection('address_user')).to have_received(:delete) do |caller, filter|
                expect(caller).to be_instance_of(Components::Caller)
                expect(filter).to have_attributes(
                  condition_tree: have_attributes(
                    aggregator: 'And',
                    conditions: [
                      have_attributes(field: 'user_id', operator: Operators::EQUAL, value: 1),
                      have_attributes(aggregator: 'Or', conditions: []),
                      have_attributes(field: 'address_id:id', operator: Operators::EQUAL, value: 1)
                    ]
                  ),
                  page: nil,
                  search: nil,
                  search_extended: nil,
                  segment: nil,
                  sort: nil
                )
              end

              expect(datasource.collection('address')).to have_received(:delete) do |caller, filter|
                expect(caller).to be_instance_of(Components::Caller)
                expect(filter).to have_attributes(
                  condition_tree: have_attributes(
                    aggregator: 'And',
                    conditions: [
                      have_attributes(aggregator: 'Or', conditions: []),
                      have_attributes(field: 'id', operator: Operators::EQUAL, value: 1),
                      have_attributes(field: 'id', operator: Operators::IN, value: [1])
                    ]
                  ),
                  page: nil,
                  search: nil,
                  search_extended: nil,
                  segment: nil,
                  sort: nil
                )
              end

              expect(result).to eq({ content: nil, status: 204 })
            end
          end
        end
      end
    end
  end
end
