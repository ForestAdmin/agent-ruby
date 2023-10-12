require 'spec_helper'
require 'singleton'
require 'ostruct'
require 'shared/caller'

module ForestAdminAgent
  module Routes
    module Resources
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Schema
      describe List do
        include_context 'with caller'
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

        before do
          user_class = Struct.new(:id, :first_name, :last_name) do
            def name
              'user'
            end
          end
          stub_const('User', user_class)

          datasource = Datasource.new
          collection = Collection.new(datasource, 'user')
          collection.add_fields(
            {
              'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
              'first_name' => ColumnSchema.new(column_type: 'String'),
              'last_name' => ColumnSchema.new(column_type: 'String')
            }
          )
          allow(collection).to receive(:list).and_return(
            [
              User.new(id: 1, first_name: 'foo', last_name: 'foo')
            ]
          )
          allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)

          datasource.add_collection(collection)
          ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(datasource)
          ForestAdminAgent::Builder::AgentFactory.instance.build
        end

        it 'return an serialized content' do
          result = list.handle_request(args)

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
                'links' => { 'self' => 'forest/user/1' }
              }
            ],
            'included' => []
          )
        end

        it 'adds the route forest_list' do
          list.setup_routes
          expect(list.routes.include?('forest_list')).to be true
          expect(list.routes.length).to eq 1
        end
      end
    end
  end
end
