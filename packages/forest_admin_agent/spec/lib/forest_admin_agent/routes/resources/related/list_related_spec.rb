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

        describe ListRelated do
          include_context 'with caller'
          include_context 'with readable related collections'
          subject(:list) { described_class.new }
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
            user_class = Struct.new(:id, :first_name, :last_name, :category_id)
            stub_const('User', user_class)

            datasource = Datasource.new
            collection_user = build_collection(
              name: 'user',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                  'first_name' => ColumnSchema.new(column_type: 'String'),
                  'last_name' => ColumnSchema.new(column_type: 'String'),
                  'category_id' => ColumnSchema.new(column_type: 'Number'),
                  'category' => Relations::ManyToOneSchema.new(
                    foreign_key: 'category_id',
                    foreign_collection: 'category',
                    foreign_key_target: 'id'
                  )
                }
              },
              list: [User.new(1, 'foo', 'foo', 1)]
            )
            collection_category = build_collection(
              name: 'category',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(
                    column_type: 'Number',
                    filter_operators: [Operators::EQUAL, Operators::GREATER_THAN],
                    is_primary_key: true
                  ),
                  'label' => ColumnSchema.new(column_type: 'String')
                }
              }
            )
            allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)
            datasource.add_collection(collection_user)
            datasource.add_collection(collection_category)
            ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(datasource)
            ForestAdminAgent::Builder::AgentFactory.instance.build

            @datasource = ForestAdminAgent::Facades::Container.datasource

            allow(ForestAdminAgent::Services::Permissions).to receive(:new).and_return(permissions)
            allow(permissions).to receive_messages(can?: true, get_scope: Nodes::ConditionTreeBranch.new('Or', []))
          end

          it 'adds the route forest_related_list' do
            list.setup_routes
            expect(list.routes.include?('forest_related_list')).to be true
            expect(list.routes.length).to eq 1
          end

          # The only routes resolving against the foreign collection rather than their own, and a
          # related listing applies no search — so neither is checked against the parent.
          it 'checks the components it applies against the foreign collection' do
            args[:params]['relation_name'] = 'category'
            args[:params]['id'] = 1
            allow(ForestAdminDatasourceToolkit::Utils::Collection).to receive(:list_relation).and_return([])

            list.handle_request(args)

            expect(read_guard_calls[:query_fields]).to eq(
              [{ collection: 'category', applies: %i[filter sort] }]
            )
            expect(read_guard_calls[:projections]).to eq([{ collection: 'category', named_by_caller: false }])
          end

          context 'when call without filters' do
            it 'call list_relation with expected args' do
              args[:params]['relation_name'] = 'category'
              args[:params]['id'] = 1
              allow(ForestAdminDatasourceToolkit::Utils::Collection).to receive(:list_relation).and_return([])
              list.handle_request(args)

              expect(ForestAdminDatasourceToolkit::Utils::Collection).to have_received(:list_relation) do
              |collection, id, relation_name, caller, foreign_filter, projection|
                expect(caller).to be_instance_of(Components::Caller)
                expect(collection.name).to eq('user')
                expect(id).to eq({ 'id' => 1 })
                expect(relation_name).to eq('category')
                expect(foreign_filter).to have_attributes(
                  condition_tree: have_attributes(aggregator: 'Or', conditions: []),
                  page: be_instance_of(ForestAdminDatasourceToolkit::Components::Query::Page),
                  search: nil,
                  search_extended: nil,
                  segment: nil,
                  sort: [{ ascending: true, field: 'id' }]
                )
                expect(projection).to eq(%w[id label])
              end
            end
          end

          context 'when the Forest-Projection header is sent' do
            it 'call list_relation with the projection read from the header' do
              args[:params]['relation_name'] = 'category'
              args[:params]['id'] = 1
              args[:headers]['HTTP_FOREST_PROJECTION'] = 'label'
              args[:params][:fields] = { 'category' => 'id' }
              allow(ForestAdminDatasourceToolkit::Utils::Collection).to receive(:list_relation).and_return([])

              list.handle_request(args)

              expect(ForestAdminDatasourceToolkit::Utils::Collection).to have_received(:list_relation) do
              |_collection, _id, _relation_name, _caller, _foreign_filter, projection|
                expect(projection).to eq(%w[label id])
              end
            end

            it 'validates the header against the foreign collection, not the parent' do
              args[:params]['relation_name'] = 'category'
              args[:params]['id'] = 1
              args[:headers]['HTTP_FOREST_PROJECTION'] = 'first_name'
              allow(ForestAdminDatasourceToolkit::Utils::Collection).to receive(:list_relation).and_return([])

              expect { list.handle_request(args) }.to raise_error(
                ForestAdminAgent::Http::Exceptions::BadRequestError,
                /Invalid Forest-Projection header:.*category\.first_name/
              )
            end
          end

          context 'when checking permissions and scope' do
            it 'authorizes and scopes on the related collection, not the parent' do
              args[:params]['relation_name'] = 'category'
              args[:params]['id'] = 1
              allow(permissions).to receive(:get_scope)
                .and_return(Nodes::ConditionTreeLeaf.new('label', Operators::EQUAL, 'active'))
              allow(ForestAdminDatasourceToolkit::Utils::Collection).to receive(:list_relation).and_return([])
              list.handle_request(args)

              expect(permissions).to have_received(:can?).with(:browse, having_attributes(name: 'category'))
              expect(permissions).not_to have_received(:can?).with(:browse, having_attributes(name: 'user'))
              expect(permissions).to have_received(:get_scope).with(having_attributes(name: 'category'))
              expect(permissions).not_to have_received(:get_scope).with(having_attributes(name: 'user'))
              expect(ForestAdminDatasourceToolkit::Utils::Collection).to have_received(:list_relation) do
              |_collection, _id, _relation_name, _caller, foreign_filter, _projection|
                expect(foreign_filter.condition_tree).to have_attributes(
                  field: 'label', operator: Operators::EQUAL, value: 'active'
                )
              end
            end
          end

          context 'when call with filters' do
            it 'call list_relation with expected args' do
              args[:params]['relation_name'] = 'category'
              args[:params]['id'] = 1
              args[:params][:filters] = JSON.generate({ field: 'id', operator: Operators::GREATER_THAN, value: 7 })
              allow(ForestAdminDatasourceToolkit::Utils::Collection).to receive(:list_relation).and_return([])
              list.handle_request(args)

              expect(ForestAdminDatasourceToolkit::Utils::Collection).to have_received(:list_relation) do
              |collection, id, relation_name, caller, foreign_filter, projection|
                expect(caller).to be_instance_of(Components::Caller)
                expect(collection.name).to eq('user')
                expect(id).to eq({ 'id' => 1 })
                expect(relation_name).to eq('category')
                expect(foreign_filter).to have_attributes(
                  condition_tree: have_attributes(
                    aggregator: 'And',
                    conditions: [
                      have_attributes(aggregator: 'Or', conditions: []),
                      have_attributes(field: 'id', operator: Operators::GREATER_THAN, value: 7)
                    ]
                  ),
                  page: be_instance_of(ForestAdminDatasourceToolkit::Components::Query::Page),
                  search: nil,
                  search_extended: nil,
                  segment: nil,
                  sort: [{ ascending: true, field: 'id' }]
                )
                expect(projection).to eq(%w[id label])
              end
            end
          end
        end

        describe ListRelated, 'with a projection deeper than one relation' do
          include_context 'with caller'
          include_context 'with readable related collections'
          subject(:list) { described_class.new }
          let(:permissions) { instance_double(ForestAdminAgent::Services::Permissions) }
          let(:args) do
            {
              headers: { 'HTTP_AUTHORIZATION' => bearer, 'HTTP_FOREST_PROJECTION' => 'label,owner:company:name' },
              params: {
                'collection_name' => 'user',
                'relation_name' => 'categories',
                'id' => 1,
                'timezone' => 'Europe/Paris'
              }
            }
          end

          before do
            datasource = Datasource.new
            datasource.add_collection(
              build_collection(
                name: 'company',
                schema: { fields: {
                  'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                  'name' => ColumnSchema.new(column_type: 'String')
                } }
              )
            )
            datasource.add_collection(
              build_collection(
                name: 'owner',
                schema: { fields: {
                  'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                  'company_id' => ColumnSchema.new(column_type: 'Number'),
                  'company' => Relations::ManyToOneSchema.new(foreign_key: 'company_id',
                                                              foreign_key_target: 'id',
                                                              foreign_collection: 'company')
                } }
              )
            )
            datasource.add_collection(
              build_collection(
                name: 'category',
                schema: { fields: {
                  'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                  'label' => ColumnSchema.new(column_type: 'String'),
                  'user_id' => ColumnSchema.new(column_type: 'Number'),
                  'owner_id' => ColumnSchema.new(column_type: 'Number'),
                  'owner' => Relations::ManyToOneSchema.new(foreign_key: 'owner_id',
                                                            foreign_key_target: 'id',
                                                            foreign_collection: 'owner')
                } }
              )
            )
            datasource.add_collection(
              build_collection(
                name: 'user',
                schema: { fields: {
                  'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                  'categories' => Relations::OneToManySchema.new(origin_key: 'user_id',
                                                                 origin_key_target: 'id',
                                                                 foreign_collection: 'category')
                } }
              )
            )

            allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)
            ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(datasource)
            ForestAdminAgent::Builder::AgentFactory.instance.build
            allow(ForestAdminAgent::Services::Permissions).to receive(:new).and_return(permissions)
            allow(permissions).to receive_messages(can?: true, get_scope: nil)
            allow(ForestAdminDatasourceToolkit::Utils::Collection).to receive(:list_relation).and_return(
              [{ 'id' => 5, 'label' => 'active',
                 'owner' => { 'id' => 50, 'company' => { 'id' => 500, 'name' => 'Gnome Press' } } }]
            )
          end

          context 'when the projection goes through more than one relation' do
            it 'serializes the record at the end of the path' do
              result = list.handle_request(args)

              included = result[:content]['included']
              expect(included.map { |resource| resource['type'] }).to contain_exactly('owner', 'company')
              expect(included.find { |resource| resource['type'] == 'company' }['attributes']['name'])
                .to eq('Gnome Press')
            end
          end
        end
      end
    end
  end
end
