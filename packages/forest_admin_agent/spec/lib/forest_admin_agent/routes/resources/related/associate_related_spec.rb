require 'spec_helper'
require 'singleton'
require 'ostruct'
require 'shared/caller'
require 'json'

module ForestAdminAgent
  module Routes
    module Resources
      module Related
        include ForestAdminDatasourceToolkit
        include ForestAdminDatasourceToolkit::Schema
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
        describe AssociateRelated do
          include_context 'with caller'
          subject(:associate) { described_class.new }
          let(:args) do
            {
              headers: { 'HTTP_AUTHORIZATION' => bearer },
              params: {
                'collection_name' => 'user',
                'timezone' => 'Europe/Paris'
              }
            }
          end
          let(:permissions) { instance_double(ForestAdminAgent::Services::Permissions) }

          before do
            user_class = Struct.new(:id, :name)
            stub_const('User', user_class)
            address_class = Struct.new(:id, :location)
            stub_const('Address', address_class)

            datasource = Datasource.new
            collection_user = collection_build(
              name: 'user',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
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
                  ),
                  'addresses_poly' => Relations::PolymorphicOneToManySchema.new(
                    origin_key: 'addressable_id',
                    foreign_collection: 'address',
                    origin_key_target: 'id',
                    origin_type_field: 'addressable_type',
                    origin_type_value: 'user'
                  )
                }
              }
            )

            collection_address_user = collection_build(
              name: 'address_user',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                  'address_id' => ColumnSchema.new(column_type: 'Number'),
                  'user_id' => ColumnSchema.new(column_type: 'Number'),
                  'address' => Relations::ManyToOneSchema.new(
                    foreign_key: 'address_id',
                    foreign_collection: 'address',
                    foreign_key_target: 'id'
                  ),
                  'user' => Relations::ManyToOneSchema.new(
                    foreign_key: 'user_id',
                    foreign_collection: 'user',
                    foreign_key_target: 'id'
                  )
                }
              }
            )

            collection_address = collection_build(
              name: 'address',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
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
            datasource.add_collection(collection_address_user)
            datasource.add_collection(collection_address)
            ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(datasource)
            ForestAdminAgent::Builder::AgentFactory.instance.build

            @datasource = ForestAdminAgent::Facades::Container.datasource

            allow(ForestAdminAgent::Services::Permissions).to receive(:new).and_return(permissions)
            allow(permissions).to receive_messages(can?: true, get_scope: nil)
          end

          it 'adds the route forest_related_associate' do
            associate.setup_routes
            expect(associate.routes.include?('forest_related_associate')).to be true
            expect(associate.routes.length).to eq 1
          end

          context 'when call on one to many relation' do
            it 'call associate_one_to_many' do
              args[:params]['relation_name'] = 'address_users'
              args[:params]['data'] = [{ 'id' => 1 }]
              args[:params]['id'] = 1
              allow(@datasource.get_collection('user')).to receive(:list).and_return([User.new(1, 'foo')])
              allow(@datasource.get_collection('address_user')).to receive(:update).and_return(true)
              result = associate.handle_request(args)

              expect(@datasource.get_collection('address_user')).to have_received(:update) do |caller, filter, data|
                expect(caller).to be_instance_of(Components::Caller)
                expect(filter).to have_attributes(
                  condition_tree: have_attributes(field: 'id', operator: Operators::EQUAL, value: 1),
                  page: nil,
                  search: nil,
                  search_extended: nil,
                  segment: nil,
                  sort: nil
                )
                expect(data).to eq({ 'user_id' => 1 })
              end
              expect(result[:content]).to be_nil
              expect(result[:status]).to eq 204
            end
          end

          context 'when call on many to many relation' do
            it 'call associate_many_to_many' do
              args[:params]['relation_name'] = 'addresses'
              args[:params]['data'] = [{ 'id' => 1 }]
              args[:params]['id'] = 1
              allow(@datasource.get_collection('user')).to receive(:list).and_return([User.new(1, 'foo')])
              allow(@datasource.get_collection('address')).to receive(:list)
                .and_return([Address.new(1, 'foo location')])
              allow(@datasource.get_collection('address_user')).to receive(:create).and_return(true)
              result = associate.handle_request(args)

              expect(@datasource.get_collection('address_user')).to have_received(:create) do |caller, data|
                expect(caller).to be_instance_of(Components::Caller)
                expect(data).to eq({ 'address_id' => 1, 'user_id' => 1 })
              end
              expect(result[:content]).to be_nil
              expect(result[:status]).to eq 204
            end
          end

          context 'when call on polymorphic one to many relation' do
            it 'call associate_polymorphic_one_to_many' do
              args[:params]['relation_name'] = 'addresses_poly'
              args[:params]['data'] = [{ 'id' => 1, 'type' => 'user' }]
              args[:params]['id'] = 1
              allow(@datasource.get_collection('user')).to receive(:list).and_return([User.new(1, 'foo')])
              allow(@datasource.get_collection('address')).to receive(:update).and_return(true)
              result = associate.handle_request(args)

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
              expect(result[:content]).to be_nil
              expect(result[:status]).to eq 204
            end
          end
        end
      end
    end
  end
end
