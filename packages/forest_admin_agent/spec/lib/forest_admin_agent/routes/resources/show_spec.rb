require 'spec_helper'
require 'singleton'
require 'ostruct'
require 'shared/caller'

module ForestAdminAgent
  module Routes
    module Resources
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Schema
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      describe Show do
        include_context 'with caller'
        subject(:show) { described_class.new }
        let(:args) do
          {
            headers: { 'HTTP_AUTHORIZATION' => bearer },
            params: {
              'collection_name' => 'user',
              'timezone' => 'Europe/Paris'
            }
          }
        end

        it 'adds the route forest_list' do
          show.setup_routes
          expect(show.routes.include?('forest_show')).to be true
          expect(show.routes.length).to eq 1
        end

        describe 'handle_request' do
          before do
            user_class = Struct.new(:id, :first_name, :last_name) do
              def respond_to?(arg)
                return false if arg == :each

                super arg
              end
            end
            stub_const('User', user_class)

            @datasource = Datasource.new

            collection = instance_double(
              Collection,
              name: 'user',
              fields: {
                'id' => ColumnSchema.new(
                  column_type: 'Number',
                  is_primary_key: true,
                  filter_operators: [Operators::IN, Operators::EQUAL]
                ),
                'first_name' => ColumnSchema.new(column_type: 'String'),
                'last_name' => ColumnSchema.new(column_type: 'String')
              },
              list: [
                User.new(1, 'foo', 'foo')
              ]
            )

            allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)
            @datasource.add_collection(collection)
            ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(@datasource)
            ForestAdminAgent::Builder::AgentFactory.instance.build

            @datasource
          end

          it 'return an serialized content' do
            args[:params]['id'] = 1
            result = show.handle_request(args)

            expect(result[:name]).to eq('user')
            expect(result[:content]).to eq(
              'data' => {
                'type' => 'user',
                'id' => '1',
                'attributes' => {
                  'id' => 1,
                  'first_name' => 'foo',
                  'last_name' => 'foo'
                },
                'links' => { 'self' => 'forest/user/1' }
              },
              'included' => []
            )
          end

          it 'call collection.list with expected args' do
            args[:params]['id'] = 1
            show.handle_request(args)

            expect(@datasource.collection('user')).to have_received(:list) do |caller, filter, projection|
              caller.is_a?(Components::Caller) &&
                filter.is_a?(Components::Query::Filter) &&
                !filter.condition_tree.nil? &&
                filter.condition_tree.to_h == { field: 'id', operator: Operators::EQUAL, value: 1 } &&
                projection == %w[id first_name last_name]
            end
          end
        end
      end
    end
  end
end
