require 'spec_helper'
require 'singleton'
require 'ostruct'
require 'shared/caller'
require 'json'

module ForestAdminAgent
  module Routes
    module Resources
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
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
          user_class = Struct.new(:id, :first_name, :last_name)
          stub_const('User', user_class)

          @datasource = Datasource.new
          collection = instance_double(
            Collection,
            name: 'user',
            fields: {
              'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
              'first_name' => ColumnSchema.new(column_type: 'String'),
              'last_name' => ColumnSchema.new(column_type: 'String')
            },
            list: [User.new(1, 'foo', 'foo')]
          )
          allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)
          @datasource.add_collection(collection)
          ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(@datasource)
          ForestAdminAgent::Builder::AgentFactory.instance.build
        end

        it 'adds the route forest_list' do
          list.setup_routes
          expect(list.routes.include?('forest_list')).to be true
          expect(list.routes.length).to eq 1
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
                'links' => { 'self' => 'forest/user/1' }
              }
            ],
            'included' => []
          )
        end

        context 'when call list with simple condition tree leaf' do
          it 'call list with expected filters arg' do
            args[:params][:filters] = JSON.generate({ field: 'id', operator: 'greater_than', value: 7 })
            list.handle_request(args)

            expect(@datasource.collection('user')).to have_received(:list) do |caller, filter, projection|
              expect(caller).to be_instance_of(Components::Caller)
              expect(filter.condition_tree.to_h).to eq({ field: 'id', operator: Operators::GREATER_THAN, value: 7 })
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

            expect(@datasource.collection('user')).to have_received(:list) do |caller, filter, projection|
              expect(caller).to be_instance_of(Components::Caller)
              expect(filter.condition_tree.to_h).to eq(
                {
                  aggregator: 'And',
                  conditions: [
                    { field: 'id', operator: 'Greater_Than', value: 7 },
                    { field: 'first_name', operator: 'Contains', value: 'foo' }
                  ]
                }
              )
              expect(projection).to eq(%w[id first_name last_name])
            end
          end
        end
      end
    end
  end
end
