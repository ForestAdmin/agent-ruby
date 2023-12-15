require 'spec_helper'
require 'singleton'
require 'ostruct'
require 'shared/caller'

module ForestAdminAgent
  module Routes
    module Resources
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
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
        let(:permissions) { instance_double(ForestAdminAgent::Services::Permissions) }

        before do
          allow(ForestAdminAgent::Services::Permissions).to receive(:new).and_return(permissions)
          allow(permissions).to receive_messages(can?: true, get_scope: Nodes::ConditionTreeBranch.new('Or', []))
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

                super(arg)
              end
            end
            stub_const('Book', book_class)
            @datasource = Datasource.new
            collection = instance_double(
              Collection,
              name: 'book',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(
                    column_type: 'Number',
                    is_primary_key: true,
                    filter_operators: [Operators::IN, Operators::EQUAL]
                  ),
                  'title' => ColumnSchema.new(column_type: 'String')
                }
              }
            )

            allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)
            @datasource.add_collection(collection)
            ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(@datasource)
            ForestAdminAgent::Builder::AgentFactory.instance.build
          end

          it 'call update and return an serialized content' do
            args[:params][:data] = { attributes: { 'title' => 'Harry potter and the goblet of fire' } }
            args[:params]['id'] = '1'
            book = Book.new(1, 'Harry potter and the goblet of fire')
            allow(@datasource.get_collection('book')).to receive_messages(list: [book], update: true)
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

          it 'call update with the expected args' do
            args[:params][:data] = { attributes: { 'title' => 'Harry potter and the goblet of fire' } }
            args[:params]['id'] = '1'
            book = Book.new(1, 'Harry potter and the goblet of fire')
            allow(@datasource.get_collection('book')).to receive_messages(list: [book], update: true)
            update.handle_request(args)

            expect(@datasource.get_collection('book')).to have_received(:update) do |caller, filter, data|
              expect(caller).to be_instance_of(Components::Caller)
              expect(data).to eq({ 'title' => 'Harry potter and the goblet of fire' })
              expect(filter.condition_tree.to_h).to eq(
                aggregator: 'And',
                conditions: [
                  { field: 'id', operator: Operators::EQUAL, value: 1 },
                  { aggregator: 'Or', conditions: [] }
                ]
              )
            end
          end
        end
      end
    end
  end
end
