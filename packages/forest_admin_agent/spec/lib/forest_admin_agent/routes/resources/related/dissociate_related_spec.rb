require 'spec_helper'

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

          let(:permissions) { instance_double(ForestAdminAgent::Services::Permissions) }
          let(:forbidden) do
            ForestAdminAgent::Http::Exceptions::ForbiddenError.new("You cannot filter on 'address:id'.")
          end

          def applies_guarded_tree?(tree, guarded_tree)
            guarded_tree.every_leaf { |guarded| tree.some_leaf { |leaf| leaf.equal?(guarded) } }
          end

          before do
            datasource = Datasource.new
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
                ),
                'address_poly' => Relations::PolymorphicOneToManySchema.new(
                  origin_key: 'addressable_id',
                  foreign_collection: 'address',
                  origin_key_target: 'id',
                  origin_type_field: 'addressable_type',
                  origin_type_value: 'user'
                ),
                'locked_addresses' => Relations::ManyToManySchema.new(
                  foreign_key: 'address_id',
                  foreign_collection: 'address',
                  foreign_key_target: 'id',
                  through_collection: 'address_user',
                  origin_key: 'user_id',
                  origin_key_target: 'id',
                  is_read_only: true
                )
              }
            )

            collection_address_user = Collection.new(datasource, 'address_user')
            collection_address_user.add_fields(
              {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true,
                                         filter_operators: [Operators::IN, Operators::EQUAL]),
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
            )

            collection_address = Collection.new(datasource, 'address')
            collection_address.add_fields(
              {
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
            )
            collection_address.add_segments(['billing'])

            allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)
            datasource.add_collection(collection_user)
            datasource.add_collection(collection_address_user)
            datasource.add_collection(collection_address)
            ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(datasource)
            ForestAdminAgent::Builder::AgentFactory.instance.build

            @datasource = ForestAdminAgent::Facades::Container.datasource

            allow(ForestAdminAgent::Services::Permissions).to receive(:new).and_return(permissions)
            allow(permissions).to receive_messages(can?: true, get_scope: nil, assert_can_read_query_fields: nil)
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
              allow(@datasource.get_collection('address_user')).to receive(:update).and_return(true)

              args[:params]['relation_name'] = 'address_users'
              args[:params][:data] = [{ 'id' => 1 }]
              args[:params]['id'] = 1

              result = dissociate.handle_request(args)

              expect(permissions).to have_received(:can?).with(:edit, @datasource.get_collection('address_user'))
              expect(permissions).not_to have_received(:can?).with(:edit, @datasource.get_collection('user'))
              expect(@datasource.get_collection('address_user')).to have_received(:update) do |caller, filter, data|
                expect(caller).to be_instance_of(Components::Caller)
                expect(filter).to have_attributes(
                  condition_tree: have_attributes(
                    aggregator: 'And',
                    conditions: [
                      have_attributes(field: 'id', operator: Operators::EQUAL, value: 1),
                      have_attributes(field: 'user_id', operator: Operators::EQUAL, value: 1)
                    ]
                  ),
                  page: nil,
                  search: nil,
                  search_extended: false,
                  segment: nil,
                  sort: nil
                )
                expect(data).to eq({ 'user_id' => nil })
              end

              expect(result).to eq({ content: nil, status: 204 })
            end

            it 'call dissociate_or_delete_one_to_many with deletion' do
              allow(@datasource.get_collection('address_user')).to receive(:delete).and_return(true)
              allow(@datasource.get_collection('address')).to receive(:delete).and_return(true)

              args[:params][:delete] = true
              args[:params]['relation_name'] = 'address_users'
              args[:params][:data] = [{ 'id' => 1 }]
              args[:params]['id'] = 1

              result = dissociate.handle_request(args)

              expect(permissions).to have_received(:can?).with(:delete, @datasource.get_collection('address_user'))
              expect(@datasource.get_collection('address_user')).to have_received(:delete) do |caller, filter|
                expect(caller).to be_instance_of(Components::Caller)
                expect(filter).to have_attributes(
                  condition_tree: have_attributes(
                    aggregator: 'And',
                    conditions: [
                      have_attributes(field: 'id', operator: Operators::EQUAL, value: 1),
                      have_attributes(field: 'user_id', operator: Operators::EQUAL, value: 1)
                    ]
                  ),
                  page: nil,
                  search: nil,
                  search_extended: false,
                  segment: nil,
                  sort: nil
                )
              end

              expect(result).to eq({ content: nil, status: 204 })
            end

            it 'call dissociate_or_delete_one_to_many with deletion on multiple records' do
              allow(@datasource.get_collection('address_user')).to receive(:delete).and_return(true)
              allow(@datasource.get_collection('address')).to receive(:delete).and_return(true)

              args[:params][:delete] = true
              args[:params]['relation_name'] = 'address_users'
              args[:params][:data] = {
                attributes: {
                  ids: [{ 'id' => '1', 'type' => 'address_user' }],
                  all_records: true,
                  all_records_ids_excluded: ['2']
                }
              }
              args[:params]['id'] = 1

              result = dissociate.handle_request(args)

              expect(permissions).to have_received(:can?).with(:delete, @datasource.get_collection('address_user'))
              expect(@datasource.get_collection('address_user')).to have_received(:delete) do |caller, filter|
                expect(caller).to be_instance_of(Components::Caller)
                expect(filter).to have_attributes(
                  condition_tree: have_attributes(
                    aggregator: 'And',
                    conditions: [
                      have_attributes(field: 'id', operator: Operators::NOT_EQUAL, value: 2),
                      have_attributes(field: 'user_id', operator: Operators::EQUAL, value: 1)
                    ]
                  ),
                  page: nil,
                  search: nil,
                  search_extended: false,
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
                'Expected no empty id list'
              )
            end

            it 'refuses to dissociate a read-only relation (any type, not just OneToOne, can be ' \
               'marked is_read_only now that it lives on the shared RelationSchema)' do
              allow(@datasource.get_collection('address_user')).to receive(:delete)

              args[:params]['relation_name'] = 'locked_addresses'
              args[:params][:data] = [{ 'id' => 1 }]
              args[:params]['id'] = 1

              expect { dissociate.handle_request(args) }
                .to raise_error(ForestAdminDatasourceToolkit::Exceptions::ValidationError,
                                'Field locked_addresses is not editable')
              expect(@datasource.get_collection('address_user')).not_to have_received(:delete)
            end

            it 'call dissociate_or_delete_many_to_many without deletion' do
              allow(@datasource.get_collection('address_user'))
                .to receive_messages(list: [AddressUser.new(1, 1, 1)], delete: true)

              args[:params]['relation_name'] = 'addresses'
              args[:params][:data] = [{ 'id' => 1 }]
              args[:params]['id'] = 1

              result = dissociate.handle_request(args)

              expect(permissions).to have_received(:can?).with(:edit, @datasource.get_collection('address'))
              expect(permissions).not_to have_received(:can?).with(:edit, @datasource.get_collection('user'))
              expect(@datasource.get_collection('address_user')).to have_received(:delete) do |caller, filter|
                expect(caller).to be_instance_of(Components::Caller)
                expect(filter).to have_attributes(
                  condition_tree: have_attributes(
                    aggregator: 'And',
                    conditions: [
                      have_attributes(field: 'user_id', operator: Operators::EQUAL, value: 1),
                      have_attributes(field: 'address:id', operator: Operators::EQUAL, value: 1)
                    ]
                  ),
                  page: nil,
                  search: nil,
                  search_extended: false,
                  segment: nil,
                  sort: nil
                )
              end

              expect(result).to eq({ content: nil, status: 204 })
            end

            it 'call dissociate_or_delete_many_to_many with deletion' do
              allow(@datasource.get_collection('address_user')).to receive_messages(list: [AddressUser.new(1, 1, 1)],
                                                                                    delete: true)
              allow(@datasource.get_collection('address')).to receive(:delete).and_return(true)

              args[:params][:delete] = true
              args[:params]['relation_name'] = 'addresses'
              args[:params][:data] = [{ 'id' => 1 }]
              args[:params]['id'] = 1

              result = dissociate.handle_request(args)

              expect(permissions).to have_received(:can?).with(:delete, @datasource.get_collection('address'))
              expect(@datasource.get_collection('address_user')).to have_received(:delete) do |caller, filter|
                expect(caller).to be_instance_of(Components::Caller)
                expect(filter).to have_attributes(
                  condition_tree: have_attributes(
                    aggregator: 'And',
                    conditions: [
                      have_attributes(field: 'user_id', operator: Operators::EQUAL, value: 1),
                      have_attributes(field: 'address:id', operator: Operators::EQUAL, value: 1)
                    ]
                  ),
                  page: nil,
                  search: nil,
                  search_extended: false,
                  segment: nil,
                  sort: nil
                )
              end

              expect(@datasource.get_collection('address')).to have_received(:delete) do |caller, filter|
                expect(caller).to be_instance_of(Components::Caller)
                expect(filter).to have_attributes(
                  condition_tree: have_attributes(
                    aggregator: 'And',
                    conditions: [
                      have_attributes(field: 'id', operator: Operators::EQUAL, value: 1),
                      have_attributes(field: 'id', operator: Operators::IN, value: [1])
                    ]
                  ),
                  page: nil,
                  search: nil,
                  search_extended: false,
                  segment: nil,
                  sort: nil
                )
              end

              expect(result).to eq({ content: nil, status: 204 })
            end

            context 'when the select-all carries the caller filters' do
              let(:address_user) { @datasource.get_collection('address_user') }
              let(:address) { @datasource.get_collection('address') }

              before do
                args[:params]['id'] = 1
                args[:params][:data] = {
                  attributes: {
                    ids: [],
                    all_records: true,
                    all_records_ids_excluded: [],
                    all_records_subset_query: {
                      filters: JSON.generate({ field: 'address:id', operator: 'equal', value: 3 }),
                      search: 'paris'
                    }
                  }
                }
              end

              context 'with a one-to-many' do
                let(:filtered_on_address_id) do
                  have_attributes(field: 'address:id', operator: Operators::EQUAL, value: 3)
                end

                before do
                  allow(address_user).to receive_messages(update: true, delete: true)
                  args[:params]['relation_name'] = 'address_users'
                end

                { 'dissociate' => [:update, [{ 'user_id' => nil }]], 'delete' => [:delete, []] }
                  .each do |mode, (written, written_patch)|
                  it "guards the child collection with the very filter it then applies (#{mode})" do
                    args[:params][:delete] = true if mode == 'delete'

                    dissociate.handle_request(args)

                    guarded_tree = nil
                    expect(permissions).to have_received(:assert_can_read_query_fields).once do |collection, applied|
                      expect(collection.equal?(address_user))
                        .to be(true), "expected the address_user collection, got #{collection.class}"
                      expect(applied.except(:condition_tree)).to eq(search: 'paris', search_extended: false)
                      expect(applied[:condition_tree].to_h)
                        .to eq(field: 'address:id', operator: Operators::EQUAL, value: 3)
                      guarded_tree = applied[:condition_tree]
                    end
                    expect(address_user).to have_received(written).once do |caller, filter, *patch|
                      expect(caller).to be_instance_of(Components::Caller)
                      expect(filter).to have_attributes(
                        search: 'paris', search_extended: false, segment: nil, page: nil, sort: nil
                      )
                      expect(applies_guarded_tree?(filter.condition_tree, guarded_tree)).to be true
                      expect(filter.condition_tree.to_h).to eq(
                        aggregator: 'And',
                        conditions: [
                          { field: 'address:id', operator: Operators::EQUAL, value: 3 },
                          { field: 'user_id', operator: Operators::EQUAL, value: 1 }
                        ]
                      )
                      expect(patch).to eq(written_patch)
                    end
                  end
                end

                it 'writes nothing when the guard refuses a filtered field' do
                  allow(permissions).to receive(:assert_can_read_query_fields)
                    .with(address_user, hash_including(condition_tree: filtered_on_address_id))
                    .and_raise(forbidden)
                  args[:params][:delete] = true

                  expect { dissociate.handle_request(args) }.to raise_error(
                    ForestAdminAgent::Http::Exceptions::ForbiddenError,
                    /You cannot filter on 'address:id'/
                  )
                  expect(address_user).not_to have_received(:delete)
                  expect(address_user).not_to have_received(:update)
                end
              end

              context 'with a many-to-many' do
                let(:forbidden) { ForestAdminAgent::Http::Exceptions::ForbiddenError.new("You cannot filter on 'id'.") }
                let(:targets_of_parent_tree) do
                  {
                    aggregator: 'And',
                    conditions: [
                      { field: 'id', operator: Operators::EQUAL, value: 3 },
                      { field: 'id', operator: Operators::IN, value: [9] }
                    ]
                  }
                end
                let(:filtered_on_id) { have_attributes(field: 'id', operator: Operators::EQUAL, value: 3) }

                before do
                  allow(address_user).to receive_messages(list: [AddressUser.new(1, 1, 9)], delete: true)
                  allow(address).to receive_messages(list: [Address.new(9, 'paris')], delete: true)
                  args[:params]['relation_name'] = 'addresses'
                  args[:params][:data][:attributes][:all_records_subset_query][:filters] =
                    JSON.generate({ field: 'id', operator: 'equal', value: 3 })
                end

                def guarded_tree
                  tree = nil
                  expect(permissions).to have_received(:assert_can_read_query_fields).once do |collection, applied|
                    expect(collection.equal?(address)).to be(true), "expected the address collection, got #{collection.class}"
                    expect(applied.except(:condition_tree)).to eq(search: 'paris', search_extended: false)
                    expect(applied[:condition_tree]).to filtered_on_id
                    tree = applied[:condition_tree]
                  end
                  tree
                end

                def expect_links_of_parent_read(times)
                  expect(address_user).to have_received(:list).exactly(times).times do |caller, filter, projection|
                    expect(caller).to be_instance_of(Components::Caller)
                    expect(filter).to have_attributes(search: nil, segment: nil, page: nil, sort: nil)
                    expect(filter.condition_tree.to_h).to eq(
                      aggregator: 'And',
                      conditions: [
                        { field: 'user_id', operator: Operators::EQUAL, value: 1 },
                        { field: 'address_id', operator: Operators::PRESENT, value: nil }
                      ]
                    )
                    expect(projection).to eq(Components::Query::Projection.new(['address_id']))
                  end
                end

                def expect_targets_listed_with(guarded)
                  expect(address).to have_received(:list).once do |caller, filter, projection|
                    expect(caller).to be_instance_of(Components::Caller)
                    expect(filter).to have_attributes(
                      search: 'paris', search_extended: false, segment: nil, page: nil, sort: nil
                    )
                    expect(applies_guarded_tree?(filter.condition_tree, guarded)).to be true
                    expect(filter.condition_tree.to_h).to eq(targets_of_parent_tree)
                    expect(projection).to eq(Components::Query::Projection.new(['id']))
                  end
                end

                def expect_links_deleted_for_matched_targets
                  expect(address_user).to have_received(:delete).once do |caller, filter|
                    expect(caller).to be_instance_of(Components::Caller)
                    expect(filter).to have_attributes(
                      search: nil, search_extended: nil, segment: nil, page: nil, sort: nil
                    )
                    expect(filter.condition_tree.to_h).to eq(
                      aggregator: 'And',
                      conditions: [
                        { field: 'user_id', operator: Operators::EQUAL, value: 1 },
                        { field: 'address_id', operator: Operators::IN, value: [9] }
                      ]
                    )
                  end
                end

                it 'unlinks only the targets the guarded filter matched (dissociate)' do
                  dissociate.handle_request(args)

                  expect_targets_listed_with(guarded_tree)
                  expect_links_of_parent_read(1)
                  expect_links_deleted_for_matched_targets
                  expect(address).not_to have_received(:delete)
                end

                it 'deletes the targets with the very filter it guarded (delete)' do
                  args[:params][:delete] = true

                  dissociate.handle_request(args)

                  guarded = guarded_tree
                  expect_targets_listed_with(guarded)
                  expect_links_of_parent_read(2)
                  expect_links_deleted_for_matched_targets
                  expect(address).to have_received(:delete).once do |caller, filter|
                    expect(caller).to be_instance_of(Components::Caller)
                    expect(filter).to have_attributes(
                      search: 'paris', search_extended: false, segment: nil, page: nil, sort: nil
                    )
                    expect(applies_guarded_tree?(filter.condition_tree, guarded)).to be true
                    expect(filter.condition_tree.to_h).to eq(targets_of_parent_tree)
                  end
                end

                it 'touches neither the through nor the target collection when refused' do
                  allow(permissions).to receive(:assert_can_read_query_fields)
                    .with(address, hash_including(condition_tree: filtered_on_id))
                    .and_raise(forbidden)
                  args[:params][:delete] = true

                  expect { dissociate.handle_request(args) }.to raise_error(
                    ForestAdminAgent::Http::Exceptions::ForbiddenError,
                    /You cannot filter on 'id'/
                  )
                  expect(address_user).not_to have_received(:delete)
                  expect(address).not_to have_received(:delete)
                end
              end
            end

            context 'with PolymorphicOneToMany' do
              it 'call dissociate_or_delete_one_to_many without deletion' do
                allow(@datasource.get_collection('address')).to receive(:update).and_return(true)

                args[:params]['relation_name'] = 'address_poly'
                args[:params][:data] = [{ 'id' => 1 }]
                args[:params]['id'] = 1

                result = dissociate.handle_request(args)

                expect(permissions).to have_received(:can?).with(:edit, @datasource.get_collection('address'))
                expect(permissions).not_to have_received(:can?).with(:edit, @datasource.get_collection('user'))

                expect(@datasource.get_collection('address')).to have_received(:update) do |caller, filter, data|
                  expect(caller).to be_instance_of(Components::Caller)
                  expect(filter).to have_attributes(
                    condition_tree: have_attributes(
                      aggregator: 'And',
                      conditions: [
                        have_attributes(field: 'id', operator: Operators::EQUAL, value: 1),
                        have_attributes(field: 'addressable_id', operator: Operators::EQUAL, value: 1),
                        have_attributes(field: 'addressable_type', operator: Operators::EQUAL, value: 'user')
                      ]
                    ),
                    page: nil,
                    search: nil,
                    search_extended: false,
                    segment: nil,
                    sort: nil
                  )
                  expect(data).to eq({ 'addressable_id' => nil, 'addressable_type' => nil })
                end

                expect(result).to eq({ content: nil, status: 204 })
              end

              it 'call dissociate_or_delete_one_to_many with deletion' do
                allow(@datasource.get_collection('address')).to receive(:delete).and_return(true)

                args[:params][:delete] = true
                args[:params]['relation_name'] = 'address_poly'
                args[:params][:data] = [{ 'id' => 1 }]
                args[:params]['id'] = 1

                result = dissociate.handle_request(args)

                expect(permissions).to have_received(:can?).with(:delete, @datasource.get_collection('address'))

                expect(@datasource.get_collection('address')).to have_received(:delete) do |caller, filter|
                  expect(caller).to be_instance_of(Components::Caller)
                  expect(filter).to have_attributes(
                    condition_tree: have_attributes(
                      aggregator: 'And',
                      conditions: [
                        have_attributes(field: 'id', operator: Operators::EQUAL, value: 1),
                        have_attributes(field: 'addressable_id', operator: Operators::EQUAL, value: 1),
                        have_attributes(field: 'addressable_type', operator: Operators::EQUAL, value: 'user')
                      ]
                    ),
                    page: nil,
                    search: nil,
                    search_extended: false,
                    segment: nil,
                    sort: nil
                  )
                end

                expect(result).to eq({ content: nil, status: 204 })
              end

              it 'deletes only the related records a select-all search and segment match' do
                allow(@datasource.get_collection('address')).to receive(:delete).and_return(true)

                args[:params][:delete] = true
                args[:params]['relation_name'] = 'address_poly'
                args[:params]['id'] = 1
                args[:params][:data] = {
                  attributes: {
                    ids: [],
                    all_records: true,
                    all_records_ids_excluded: ['2'],
                    all_records_subset_query: { search: 'paris', segment: 'billing' }
                  }
                }

                dissociate.handle_request(args)

                expect(@datasource.get_collection('address')).to have_received(:delete) do |caller, filter|
                  expect(caller).to be_instance_of(Components::Caller)
                  expect(filter).to have_attributes(
                    condition_tree: have_attributes(
                      aggregator: 'And',
                      conditions: [
                        have_attributes(field: 'id', operator: Operators::NOT_EQUAL, value: 2),
                        have_attributes(field: 'addressable_id', operator: Operators::EQUAL, value: 1),
                        have_attributes(field: 'addressable_type', operator: Operators::EQUAL, value: 'user')
                      ]
                    ),
                    page: nil,
                    search: 'paris',
                    search_extended: false,
                    segment: 'billing',
                    sort: nil
                  )
                end
              end
            end
          end
        end
      end
    end
  end
end
