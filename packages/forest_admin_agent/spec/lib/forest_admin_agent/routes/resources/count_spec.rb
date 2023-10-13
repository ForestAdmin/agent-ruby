require 'spec_helper'
require 'singleton'
require 'ostruct'
require 'shared/caller'

module ForestAdminAgent
  module Routes
    module Resources
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Schema
      describe Count do
        include_context 'with caller'
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

        before do
          datasource = Datasource.new
          collection = Collection.new(datasource, 'user')
          allow(collection).to receive(:aggregate).and_return(
            [
              { value: 1, group: [] }
            ]
          )
          allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)

          datasource.add_collection(collection)
          ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(datasource)
          ForestAdminAgent::Builder::AgentFactory.instance.build
        end

        it 'return an serialized content' do
          result = count.handle_request(args)

          expect(result[:name]).to eq('user')
          expect(result[:content]).to eq({ count: 1 })
        end

        it 'adds the route forest_count' do
          count.setup_routes
          expect(count.routes.include?('forest_count')).to be true
          expect(count.routes.length).to eq 1
        end
      end
    end
  end
end
