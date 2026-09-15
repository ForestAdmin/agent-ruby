require 'spec_helper'
require 'singleton'
require 'ostruct'

require 'json'

module ForestAdminAgent
  module Routes
    module Resources
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminDatasourceToolkit::Schema
      include ForestAdminDatasourceToolkit::Exceptions

      describe List do
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
          user_class = Struct.new(:id, :first_name, :last_name)
          stub_const('User', user_class)

          datasource = Datasource.new
          collection = build_collection(
            name: 'user',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', filter_operators: [Operators::EQUAL, Operators::GREATER_THAN, Operators::LESS_THAN], is_primary_key: true),
                'first_name' => ColumnSchema.new(column_type: 'String', filter_operators: [Operators::EQUAL, Operators::CONTAINS]),
                'last_name' => ColumnSchema.new(column_type: 'String')
              }
            },
            list: [User.new(1, 'foo', 'foo')]
          )

          allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)
          datasource.add_collection(collection)
          ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(datasource)
          ForestAdminAgent::Builder::AgentFactory.instance.build
          @datasource = ForestAdminAgent::Facades::Container.datasource
          allow(@datasource.get_collection('user')).to receive(:list).and_return([User.new(1, 'foo', 'foo')])

          allow(ForestAdminAgent::Services::Permissions).to receive(:new).and_return(permissions)
          allow(permissions).to receive_messages(
            can?: true,
            get_scope: nil,
            get_user_data: {
              id: 1,
              firstName: 'John',
              lastName: 'Doe',
              fullName: 'John Doe',
              email: 'johndoe@forestadmin.com',
              tags: { 'foo' => 'bar' },
              roleId: 1,
              permissionLevel: 'admin'
            },
            get_team: { id: 100, name: 'Operations' }
          )
        end

        it 'adds the route forest_list' do
          list.setup_routes
          expect(list.routes.include?('forest_list')).to be true
          expect(list.routes.length).to eq 1
        end

        it 'checks every query component it applies, against its own collection' do
          list.handle_request(args)

          expect(read_guard_calls[:query_fields]).to eq(
            [{ collection: 'user', applies: %i[filter sort search search_extended] }]
          )
        end

        it 'hands the guard the extended flag it parsed, not a default' do
          args[:params][:searchExtended] = '1'
          list.handle_request(args)

          expect(read_guard_calls[:search_extended]).to eq([true])
        end

        it 'refuses a projection the caller named on its own collection' do
          args[:params][:fields] = { 'user' => 'id,first_name' }
          list.handle_request(args)

          expect(read_guard_calls[:projections]).to eq([{ collection: 'user', named_by_caller: true }])
        end

        it 'redacts rather than refuses the expansion the caller never asked for' do
          list.handle_request(args)

          expect(read_guard_calls[:projections]).to eq([{ collection: 'user', named_by_caller: false }])
        end

        it 'answers a denied query field with a 403 rather than a listing' do
          allow(permissions).to receive(:assert_can_read_query_fields).and_raise(
            ForestAdminAgent::Http::Exceptions::ForbiddenError.new(
              "You cannot filter on 'category:label': you are not allowed to read the 'category' collection."
            )
          )

          expect { list.handle_request(args) }.to raise_error(
            ForestAdminAgent::Http::Exceptions::ForbiddenError,
            /You cannot filter on 'category:label'/
          )
        end

        it 'return an serialized content' do
          result = list.handle_request(args)

          expect(result[:name]).to eq('user')
          expect(result[:content]).to eq(
            'data' => [
              {
                'type' => 'user',
                'id' => '1',
                'attributes' => {
                  'id' => 1,
                  'first_name' => 'foo',
                  'last_name' => 'foo'
                },
                'links' => { 'self' => '/forest/user/1' }
              }
            ],
            'included' => [],
            'meta' => { decorators: [] }
          )
        end

        context 'when the Forest-Projection header is sent' do
          it 'gives precedence to the header over the fields params' do
            args[:headers]['HTTP_FOREST_PROJECTION'] = 'first_name'
            args[:params][:fields] = { 'user' => 'last_name' }
            list.handle_request(args)

            expect(@datasource.get_collection('user')).to have_received(:list) do |_caller, _filter, projection|
              expect(projection).to eq(%w[first_name id])
            end
          end

          it 'does not fall back to the fields params when the header is invalid' do
            args[:headers]['HTTP_FOREST_PROJECTION'] = 'field-that-do-not-exist'
            args[:params][:fields] = { 'user' => 'last_name' }

            expect { list.handle_request(args) }.to raise_error(
              Http::Exceptions::BadRequestError,
              /Invalid Forest-Projection header:/
            )
          end
        end

        context 'when call list with simple condition tree leaf' do
          it 'call list with expected filters arg' do
            args[:params][:filters] = JSON.generate({ field: 'id', operator: 'greater_than', value: 7 })
            list.handle_request(args)

            expect(@datasource.get_collection('user')).to have_received(:list) do |caller, filter, projection|
              expect(caller).to be_instance_of(Components::Caller)
              expect(filter.condition_tree.to_h).to eq(field: 'id', operator: Operators::GREATER_THAN, value: 7)
              expect(projection).to eq(%w[id first_name last_name])
            end
          end
        end

        context 'when call list with condition tree branch' do
          it 'call list with expected filters arg' do
            args[:params][:filters] = JSON.generate(
              {
                aggregator: 'and',
                conditions: [
                  { field: 'id', operator: 'greater_than', value: 7 },
                  { field: 'first_name', operator: 'contains', value: 'foo' }
                ]
              }
            )
            list.handle_request(args)

            expect(@datasource.get_collection('user')).to have_received(:list) do |caller, filter, projection|
              expect(caller).to be_instance_of(Components::Caller)
              expect(filter.condition_tree.to_h).to eq(
                {
                  aggregator: 'And',
                  conditions: [
                    { field: 'id', operator: 'greater_than', value: 7 },
                    { field: 'first_name', operator: 'contains', value: 'foo' }
                  ]
                }
              )
              expect(projection).to eq(%w[id first_name last_name])
            end
          end
        end

        it 'throws an error when the filter operator is not allowed' do
          args[:params][:filters] = JSON.generate({ field: 'id', operator: 'shorter_than', value: 7 })
          expect { list.handle_request(args) }.to raise_error(ForestException, "The given operator 'shorter_than' is not supported by the column: 'id'. The column is not filterable")
        end
      end

      describe List, 'with a projection deeper than one relation' do
        include_context 'with caller'
        include_context 'with readable related collections'
        subject(:list) { described_class.new }
        let(:permissions) { instance_double(ForestAdminAgent::Services::Permissions) }

        before do
          allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)
          allow(ForestAdminAgent::Services::Permissions).to receive(:new).and_return(permissions)
          allow(permissions).to receive_messages(can?: true, get_scope: nil, get_team: { id: 100, name: 'Ops' })
        end

        context 'when the projection goes through more than one relation' do
          let(:args) do
            {
              headers: { 'HTTP_AUTHORIZATION' => bearer, 'HTTP_FOREST_PROJECTION' => 'title,author:company:name' },
              params: { 'collection_name' => 'book', 'timezone' => 'Europe/Paris' }
            }
          end

          before do
            datasource = Datasource.new
            datasource.add_collection(
              build_collection(
                name: 'company',
                schema: { fields: {
                  'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true,
                                           filter_operators: [Operators::EQUAL]),
                  'name' => ColumnSchema.new(column_type: 'String')
                } }
              )
            )
            datasource.add_collection(
              build_collection(
                name: 'author',
                schema: { fields: {
                  'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true,
                                           filter_operators: [Operators::EQUAL]),
                  'company_id' => ColumnSchema.new(column_type: 'Number'),
                  'company' => Relations::ManyToOneSchema.new(foreign_key: 'company_id',
                                                              foreign_key_target: 'id',
                                                              foreign_collection: 'company')
                } }
              )
            )
            datasource.add_collection(
              build_collection(
                name: 'book',
                schema: { fields: {
                  'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true,
                                           filter_operators: [Operators::EQUAL]),
                  'title' => ColumnSchema.new(column_type: 'String'),
                  'author_id' => ColumnSchema.new(column_type: 'Number'),
                  'author' => Relations::ManyToOneSchema.new(foreign_key: 'author_id',
                                                             foreign_key_target: 'id',
                                                             foreign_collection: 'author')
                } }
              )
            )
            ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(datasource)
            ForestAdminAgent::Builder::AgentFactory.instance.build
            @datasource = ForestAdminAgent::Facades::Container.datasource
            allow(@datasource.get_collection('book')).to receive(:list).and_return(
              [
                { 'id' => 1, 'title' => 'Foundation',
                  'author' => { 'id' => 10, 'company' => { 'id' => 100, 'name' => 'Gnome Press' } } },
                { 'id' => 2, 'title' => 'I, Robot',
                  'author' => { 'id' => 10, 'company' => { 'id' => 100, 'name' => 'Gnome Press' } } }
              ]
            )
          end

          it 'serializes the record at the end of the path once for the whole page' do
            result = list.handle_request(args)

            included = result[:content]['included']
            expect(included.map { |resource| resource['type'] }).to contain_exactly('author', 'company')
            expect(included.find { |resource| resource['type'] == 'company' }['attributes']['name'])
              .to eq('Gnome Press')
          end
        end
      end
    end
  end
end
