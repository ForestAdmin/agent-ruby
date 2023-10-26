require 'spec_helper'
require 'singleton'
require 'ostruct'
require 'shared/caller'

module ForestAdminAgent
  module Routes
    module Resources
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Schema
      describe Update do
        include_context 'with caller'
        subject(:update) { described_class.new }
        let(:args) do
          {
            headers: { 'HTTP_AUTHORIZATION' => bearer },
            params: {
              'collection_name' => 'book',
              'timezone' => 'Europe/Paris'
            }
          }
        end

        it 'adds the route forest_store' do
          update.setup_routes
          expect(update.routes.include?('forest_update')).to be true
          expect(update.routes.length).to eq 1
        end

        describe 'handle_request' do
          before do
            book_class = Struct.new(:id, :title, :published_at, :price) do
              def respond_to?(arg)
                return false if arg == :each

                super arg
              end
            end
            stub_const('Book', book_class)
          end

          it 'call update and return an serialized content' do
            datasource = Datasource.new
            collection = Collection.new(datasource, 'book')
            collection.add_fields(
              {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'title' => ColumnSchema.new(column_type: 'String')
              }
            )
            allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)
            datasource.add_collection(collection)
            ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(datasource)
            ForestAdminAgent::Builder::AgentFactory.instance.build

            args[:params][:data] = { attributes: { 'title' => 'Harry potter and the goblet of fire' } }
            args[:params]['id'] = '1'
            book = Book.new(1, 'Harry potter and the goblet of fire')
            allow(collection).to receive_messages(list: [book], update: true)
            result = update.handle_request(args)
            expect(result[:name]).to eq('book')
            expect(result[:content]).to eq(
              'data' =>
                {
                  'type' => 'book',
                  'id' => '1',
                  'attributes' => {
                    'id' => 1,
                    'title' => 'Harry potter and the goblet of fire'
                  },
                  'links' => { 'self' => 'forest/book/1' }
                }
            )
          end
        end
      end
    end
  end
end
