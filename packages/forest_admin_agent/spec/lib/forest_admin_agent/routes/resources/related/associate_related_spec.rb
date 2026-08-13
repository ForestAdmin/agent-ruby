require 'spec_helper'
require 'singleton'
require 'ostruct'

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
            collection_user = build_collection(
              name: 'user',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true,
                                           filter_operators: [Operators::IN, Operators::EQUAL]),
                  'name' => ColumnSchema.new(column_type: 'String'),
                  'reference' => ColumnSchema.new(column_type: 'String'),
                  'addresses' => Relations::ManyToManySchema.new(
                    foreign_key: 'address_id',
                    foreign_collection: 'address',
                    foreign_key_target: 'id',
                    through_collection: 'address_user',
                    origin_key: 'user_id',
                    origin_key_target: 'id'
                  ),
                  'addresses_by_code' => Relations::ManyToManySchema.new(
                    foreign_key: 'address_code',
                    foreign_collection: 'address',
                    foreign_key_target: 'code',
                    through_collection: 'address_user',
                    origin_key: 'user_reference',
                    origin_key_target: 'reference'
                  ),
                  'address_users' => Relations::OneToManySchema.new(
                    origin_key: 'user_id',
                    origin_key_target: 'id',
                    foreign_collection: 'address_user'
                  ),
                  'notes' => Relations::OneToManySchema.new(
                    origin_key: 'user_id',
                    origin_key_target: 'id',
                    foreign_collection: 'note'
                  ),
                  'notes_by_chapter' => Relations::ManyToManySchema.new(
                    foreign_key: 'note_chapter',
                    foreign_collection: 'note',
                    foreign_key_target: 'chapter',
                    through_collection: 'note_user',
                    origin_key: 'user_id',
                    origin_key_target: 'id'
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

            collection_address_user = build_collection(
              name: 'address_user',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true,
                                           filter_operators: [Operators::IN, Operators::EQUAL]),
                  'address_id' => ColumnSchema.new(column_type: 'Number'),
                  'user_id' => ColumnSchema.new(column_type: 'Number'),
                  'address_code' => ColumnSchema.new(column_type: 'String'),
                  'user_reference' => ColumnSchema.new(column_type: 'String'),
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

            collection_address = build_collection(
              name: 'address',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true,
                                           filter_operators: [Operators::IN, Operators::EQUAL]),
                  'location' => ColumnSchema.new(column_type: 'String'),
                  'code' => ColumnSchema.new(column_type: 'String'),
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

            collection_note = build_collection(
              name: 'note',
              schema: {
                fields: {
                  'book_id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true,
                                                filter_operators: [Operators::IN, Operators::EQUAL]),
                  'chapter' => ColumnSchema.new(column_type: 'String', is_primary_key: true,
                                                filter_operators: [Operators::IN, Operators::EQUAL]),
                  'user_id' => ColumnSchema.new(column_type: 'Number')
                }
              }
            )

            collection_note_user = build_collection(
              name: 'note_user',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                  'user_id' => ColumnSchema.new(column_type: 'Number'),
                  'note_chapter' => ColumnSchema.new(column_type: 'String')
                }
              }
            )

            allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)
            datasource.add_collection(collection_user)
            datasource.add_collection(collection_note)
            datasource.add_collection(collection_note_user)
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

          it 'checks the edit permission on the foreign collection before parsing any id' do
            allow(permissions).to receive(:can?)
              .and_raise(ForestAdminAgent::Http::Exceptions::ForbiddenError)

            args[:params]['relation_name'] = 'addresses'
            args[:params]['data'] = [{ 'id' => 'malformed|id' }]
            args[:params]['id'] = 'malformed|id'

            expect { associate.handle_request(args) }
              .to raise_error(ForestAdminAgent::Http::Exceptions::ForbiddenError)
            expect(permissions).to have_received(:can?) do |action, collection|
              expect(action).to eq(:edit)
              expect(collection.name).to eq('address')
            end
          end

          context 'when call on one to many relation' do
            before do
              args[:params]['relation_name'] = 'address_users'
              args[:params]['data'] = [{ 'id' => 1 }]
              args[:params]['id'] = 1
              allow(permissions).to receive(:get_scope)
                .and_return(Nodes::ConditionTreeLeaf.new('user_id', Operators::NOT_EQUAL, 99))
              allow(@datasource.get_collection('user')).to receive(:list).and_return([User.new(1, 'foo')])
              allow(@datasource.get_collection('address_user')).to receive(:update).and_return(true)
            end

            it 'matches every key column when the target has a composite primary key' do
              args[:params]['relation_name'] = 'notes'
              args[:params]['data'] = [{ 'id' => '7|intro' }]
              allow(@datasource.get_collection('note')).to receive(:update).and_return(true)

              associate.handle_request(args)

              expect(@datasource.get_collection('note')).to have_received(:update) do |_caller, filter, data|
                expect(filter.condition_tree).to have_attributes(
                  aggregator: 'And',
                  conditions: [
                    have_attributes(field: 'book_id', operator: Operators::EQUAL, value: 7),
                    have_attributes(field: 'chapter', operator: Operators::EQUAL, value: 'intro'),
                    have_attributes(field: 'user_id', operator: Operators::NOT_EQUAL, value: 99)
                  ]
                )
                expect(data).to eq({ 'user_id' => 1 })
              end
            end

            it 'call associate_one_to_many' do
              result = associate.handle_request(args)

              expect(permissions).to have_received(:can?) do |action, collection|
                expect(action).to eq(:edit)
                expect(collection.name).to eq('address_user')
              end
              expect(permissions).to have_received(:get_scope) do |collection|
                expect(collection.name).to eq('address_user')
              end
              expect(@datasource.get_collection('address_user')).to have_received(:update) do |caller, filter, data|
                expect(caller).to be_instance_of(Components::Caller)
                expect(filter).to have_attributes(
                  condition_tree: have_attributes(
                    aggregator: 'And',
                    conditions: [
                      have_attributes(field: 'id', operator: Operators::EQUAL, value: 1),
                      have_attributes(field: 'user_id', operator: Operators::NOT_EQUAL, value: 99)
                    ]
                  ),
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
            before do
              args[:params]['relation_name'] = 'addresses'
              args[:params]['data'] = [{ 'id' => 1 }]
              args[:params]['id'] = 1
              allow(permissions).to receive(:get_scope)
                .and_return(Nodes::ConditionTreeLeaf.new('location', Operators::EQUAL, 'paris'))
              allow(@datasource.get_collection('user')).to receive(:list).and_return([User.new(1, 'foo')])
              allow(@datasource.get_collection('address_user')).to receive(:create).and_return(true)
            end

            it 'call associate_many_to_many' do
              allow(@datasource.get_collection('address')).to receive(:list)
                .and_return([{ 'id' => 1, 'location' => 'paris' }])
              result = associate.handle_request(args)

              expect(permissions).to have_received(:can?) do |action, collection|
                expect(action).to eq(:edit)
                expect(collection.name).to eq('address')
              end
              expect(permissions).to have_received(:get_scope) do |collection|
                expect(collection.name).to eq('address')
              end
              expect(@datasource.get_collection('address_user')).to have_received(:create) do |caller, data|
                expect(caller).to be_instance_of(Components::Caller)
                expect(data).to eq({ 'address_id' => 1, 'user_id' => 1 })
              end
              expect(result[:content]).to be_nil
              expect(result[:status]).to eq 204
            end

            it 'searches the target with the scope of the foreign collection' do
              allow(@datasource.get_collection('address')).to receive(:list)
                .and_return([{ 'id' => 1, 'location' => 'paris' }])
              associate.handle_request(args)

              expect(@datasource.get_collection('address')).to have_received(:list) do |caller, filter, projection|
                expect(caller).to be_instance_of(Components::Caller)
                expect(filter).to have_attributes(
                  condition_tree: have_attributes(
                    aggregator: 'And',
                    conditions: [
                      have_attributes(field: 'id', operator: Operators::EQUAL, value: 1),
                      have_attributes(field: 'location', operator: Operators::EQUAL, value: 'paris')
                    ]
                  )
                )
                expect(projection).to eq(['id'])
              end
            end

            it 'does not create the through record when the target is out of scope' do
              allow(@datasource.get_collection('address')).to receive(:list).and_return([])
              result = associate.handle_request(args)

              expect(@datasource.get_collection('address_user')).not_to have_received(:create)
              expect(result[:content]).to be_nil
              expect(result[:status]).to eq 204
            end

            context 'when the target has a composite primary key' do
              before do
                args[:params]['relation_name'] = 'notes_by_chapter'
                args[:params]['data'] = [{ 'id' => '7|intro' }]
                allow(permissions).to receive(:get_scope)
                  .and_return(Nodes::ConditionTreeLeaf.new('user_id', Operators::NOT_EQUAL, 99))
                allow(@datasource.get_collection('note')).to receive(:list).and_return([{ 'chapter' => 'intro' }])
                allow(@datasource.get_collection('note_user')).to receive(:create).and_return(true)
              end

              it 'matches every key column of the target before linking it' do
                associate.handle_request(args)

                expect(@datasource.get_collection('note')).to have_received(:list) do |_caller, filter, projection|
                  expect(filter.condition_tree).to have_attributes(
                    aggregator: 'And',
                    conditions: [
                      have_attributes(field: 'book_id', operator: Operators::EQUAL, value: 7),
                      have_attributes(field: 'chapter', operator: Operators::EQUAL, value: 'intro'),
                      have_attributes(field: 'user_id', operator: Operators::NOT_EQUAL, value: 99)
                    ]
                  )
                  expect(projection).to eq(['chapter'])
                end
                expect(@datasource.get_collection('note_user')).to have_received(:create) do |_caller, data|
                  expect(data).to eq({ 'user_id' => 1, 'note_chapter' => 'intro' })
                end
              end
            end

            context 'when the relation keys target a column that is not the primary key' do
              before do
                args[:params]['relation_name'] = 'addresses_by_code'
                allow(@datasource.get_collection('user')).to receive(:list)
                  .and_return([{ 'reference' => 'REF-1' }])
                allow(@datasource.get_collection('address')).to receive(:list)
                  .and_return([{ 'code' => 'A1' }])
              end

              it 'writes the target keys in the through record, not the primary keys' do
                associate.handle_request(args)

                expect(@datasource.get_collection('address_user')).to have_received(:create) do |_caller, data|
                  expect(data).to eq({ 'user_reference' => 'REF-1', 'address_code' => 'A1' })
                end
              end

              it 'projects the foreign key target on the scoped target' do
                associate.handle_request(args)

                expect(@datasource.get_collection('address')).to have_received(:list) do |_caller, _filter, projection|
                  expect(projection).to eq(['code'])
                end
              end
            end
          end

          context 'when call on polymorphic one to many relation' do
            before do
              args[:params]['relation_name'] = 'addresses_poly'
              args[:params]['data'] = [{ 'id' => 1, 'type' => 'user' }]
              args[:params]['id'] = 1
              allow(permissions).to receive(:get_scope)
                .and_return(Nodes::ConditionTreeLeaf.new('location', Operators::EQUAL, 'paris'))
              allow(@datasource.get_collection('user')).to receive(:list).and_return([User.new(1, 'foo')])
              allow(@datasource.get_collection('address')).to receive(:update).and_return(true)
            end

            it 'call associate_polymorphic_one_to_many' do
              result = associate.handle_request(args)

              expect(permissions).to have_received(:can?) do |action, collection|
                expect(action).to eq(:edit)
                expect(collection.name).to eq('address')
              end
              expect(permissions).to have_received(:get_scope) do |collection|
                expect(collection.name).to eq('address')
              end
              expect(@datasource.get_collection('address')).to have_received(:update) do |caller, filter, data|
                expect(caller).to be_instance_of(Components::Caller)
                expect(filter).to have_attributes(
                  condition_tree: have_attributes(
                    aggregator: 'And',
                    conditions: [
                      have_attributes(field: 'id', operator: Operators::EQUAL, value: 1),
                      have_attributes(field: 'location', operator: Operators::EQUAL, value: 'paris')
                    ]
                  ),
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
