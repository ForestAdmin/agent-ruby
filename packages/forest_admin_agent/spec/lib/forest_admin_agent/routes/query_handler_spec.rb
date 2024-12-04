require 'spec_helper'
require 'shared/caller'

module ForestAdminAgent
  module Routes
    include ForestAdminDatasourceToolkit
    include ForestAdminDatasourceToolkit::Schema
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
    include ForestAdminAgent::Http::Exceptions

    describe QueryHandler do
      include_context 'with caller'

      let(:dummy_class) { Class.new { extend QueryHandler } }

      describe 'parse_query_segment' do
        let(:datasource) { datasource_build(execute_native_query: [{ id: 1 }, { id: 2 }]) }

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
          datasource_customizer = instance_double(
            ForestAdminDatasourceCustomizer::DatasourceCustomizer,
            {
              get_root_datasource_by_connection: datasource
            }
          )
          allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:customizer)
            .and_return(datasource_customizer)
          collection = collection_build(
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

        it 'return null when not provided' do
          expect(dummy_class.parse_query_segment(collection, { params: {} }, permission, caller)).to be_nil
        end

        it 'raise an error when datasource not provided' do
          expect do
            dummy_class.parse_query_segment(
              collection,
              { params: { segmentQuery: 'select id from user' } },
              permission,
              caller
            )
          end.to raise_error(UnprocessableError, "'connectionName' parameter is mandatory")
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
    end
  end
end
