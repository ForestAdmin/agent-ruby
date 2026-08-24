require 'spec_helper'
require 'singleton'
require 'ostruct'

module ForestAdminAgent
  module Routes
    module Resources
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Schema
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes

      describe Count do
        include_context 'with caller'
        include_context 'with readable related collections'
        subject(:count) { described_class.new }
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
          datasource = Datasource.new
          collection = Collection.new(datasource, 'user')
          allow(collection).to receive(:aggregate).and_return(
            [
              { 'value' => 1, 'group' => [] }
            ]
          )
          allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)

          datasource.add_collection(collection)
          ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(datasource)
          ForestAdminAgent::Builder::AgentFactory.instance.build
          @datasource = ForestAdminAgent::Facades::Container.datasource

          allow(ForestAdminAgent::Services::Permissions).to receive(:new).and_return(permissions)
          allow(permissions).to receive_messages(can?: true, get_scope: nil)
        end

        it 'adds the route forest_count' do
          count.setup_routes
          expect(count.routes.include?('forest_count')).to be true
          expect(count.routes.length).to eq 1
        end

        # A count applies no sort, so checking one would refuse a request the denied field cannot
        # reach — while its filter and search are the sharper half and stay checked.
        it 'checks only the query components it applies, against its own collection' do
          ForestAdminAgent::Facades::Container.datasource.get_collection('user').enable_count
          count.handle_request(args)

          expect(read_guard_calls[:query_fields]).to eq([{ collection: 'user', applies: %i[filter search] }])
        end

        context 'when collection is countable' do
          it 'return an serialized content' do
            ForestAdminAgent::Facades::Container.datasource.get_collection('user').enable_count
            result = count.handle_request(args)

            expect(result[:name]).to eq('user')
            expect(result[:content]).to eq({ count: 1 })
          end
        end

        context 'when collection is not countable' do
          it 'return an deactivated response' do
            result = count.handle_request(args)

            expect(result[:name]).to eq('user')
            expect(result[:content]).to eq({ count: 'deactivated' })
          end
        end
      end
    end
  end
end
