require 'spec_helper'

module ForestAdminAgent
  module Routes
    include ForestAdminDatasourceToolkit
    include ForestAdminDatasourceToolkit::Schema
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
    include ForestAdminAgent::Http::Exceptions

    describe QueryHandler do
      include_context 'with caller'

      let(:dummy_class) { Class.new { extend QueryHandler } }
      let(:datasource) { build_datasource(execute_native_query: [{ id: 1 }, { id: 2 }], build_binding_symbol: '$1') }

      let(:permission) do
        instance_double(
          ForestAdminAgent::Services::Permissions,
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
          get_team: { id: 100, name: 'Operations' },
          can_execute_query_segment?: nil
        )
      end

      let(:collection) do
        collection = build_collection(
          datasource: datasource,
          name: 'Category',
          schema: {
            fields: {
              'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true,
                                       filter_operators: [Operators::EQUAL, Operators::IN]),
              'label' => ColumnSchema.new(column_type: 'String')
            }
          }
        )

        datasource.add_collection(collection)

        collection
      end

      before do
        datasource_customizer = instance_double(ForestAdminDatasourceCustomizer::DatasourceCustomizer)
        allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:customizer)
          .and_return(datasource_customizer)
      end

      describe 'parse_query_segment' do
        it 'return null when not provided' do
          expect(dummy_class.parse_query_segment(collection, { params: {} }, permission, caller)).to be_nil
        end

        it 'raise an error when connectionName not provided' do
          expect do
            dummy_class.parse_query_segment(
              collection,
              { params: { segmentQuery: 'select id from user' } },
              permission,
              caller
            )
          end.to raise_error(UnprocessableError, 'Missing native query connection attribute')
        end

        it 'work when passed in the querystring for list' do
          args = {
            params: {
              segmentQuery: 'SELECT id from user',
              connectionName: 'primary'
            }
          }

          condition_tree = dummy_class.parse_query_segment(collection, args, permission, caller)
          expect(condition_tree.to_h).to eq({ field: 'id', operator: Operators::IN, value: [1, 2] })
        end

        it 'work with inject context variable' do
          args = {
            params: {
              segmentQuery: 'SELECT id FROM users WHERE id > {{currentUser.id}};',
              connectionName: 'primary'
            }
          }

          dummy_class.parse_query_segment(collection, args, permission, caller)
          expect(datasource).to have_received(:execute_native_query) do |connection_name, query, binds|
            expect(connection_name).to eq('primary')
            expect(query).to eq('SELECT id FROM users WHERE id > $1;')
            expect(binds).to eq([1])
          end
        end
      end

      describe 'execute_query' do
        it 'raise an error when connectionName was unknown' do
          allow(collection.datasource).to receive(:execute_native_query).and_raise(ForestAdminAgent::Http::Exceptions::NotFoundError,
                                                                                   "Native query connection 'foo' is unknown.")
          expect do
            dummy_class.execute_query(
              collection.datasource,
              'select id from user',
              'foo',
              permission,
              caller,
              {}
            )
          end.to raise_error(NotFoundError, "Native query connection 'foo' is unknown.")
        end

        it 'work when passed in the querystring for list' do
          result = dummy_class.execute_query(collection.datasource, 'SELECT id from user', 'primary', permission, caller, {})

          expect(result).to eq([{ id: 1 }, { id: 2 }])
        end

        it 'work with inject context variables' do
          dummy_class.execute_query(
            collection.datasource,
            'SELECT id FROM users WHERE id > {{foo.id}};',
            'primary',
            permission,
            caller,
            { 'foo.id' => 1 }
          )

          expect(datasource).to have_received(:execute_native_query) do |connection_name, query, binds|
            expect(connection_name).to eq('primary')
            expect(query).to eq('SELECT id FROM users WHERE id > $1;')
            expect(binds).to eq([1])
          end
        end
      end
    end
  end
end
