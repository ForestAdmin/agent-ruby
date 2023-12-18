require 'spec_helper'
require 'singleton'
require 'ostruct'
require 'shared/caller'
require 'json'

module ForestAdminAgent
  module Routes
    module Resources
      module Related
        include ForestAdminDatasourceToolkit
        include ForestAdminDatasourceToolkit::Schema
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
        describe CountRelated do
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
          let(:permissions) { instance_double(ForestAdminAgent::Services::Permissions) }

          before do
            user_class = Struct.new(:id, :first_name, :last_name)
            stub_const('User', user_class)

            @datasource = Datasource.new
            collection_user = instance_double(
              Collection,
              name: 'user',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                  'first_name' => ColumnSchema.new(column_type: 'String'),
                  'last_name' => ColumnSchema.new(column_type: 'String'),
                  'category' => Relations::ManyToOneSchema.new(
                    foreign_key: 'category_id',
                    foreign_collection: 'category',
                    foreign_key_target: 'id'
                  )
                }
              }
            )
            collection_category = instance_double(
              Collection,
              name: 'category',
              is_countable?: true,
              schema: {
                fields: {
                  'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                  'label' => ColumnSchema.new(column_type: 'String')
                }
              }
            )
            allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)
            @datasource.add_collection(collection_user)
            @datasource.add_collection(collection_category)
            ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(@datasource)
            ForestAdminAgent::Builder::AgentFactory.instance.build

            allow(ForestAdminAgent::Services::Permissions).to receive(:new).and_return(permissions)
            allow(permissions).to receive_messages(can?: true, get_scope: Nodes::ConditionTreeBranch.new('Or', []))
          end

          it 'adds the route forest_related_count' do
            count.setup_routes
            expect(count.routes.include?('forest_related_count')).to be true
            expect(count.routes.length).to eq 1
          end

          context 'when collection is countable' do
            it 'call aggregate_relation with expected args' do
              args[:params]['relation_name'] = 'category'
              args[:params]['id'] = 1
              ForestAdminAgent::Facades::Container.datasource.get_collection('category').enable_count
              allow(ForestAdminDatasourceToolkit::Utils::Collection).to receive(:aggregate_relation)
                .and_return([{ value: 1 }])
              count.handle_request(args)

              expect(ForestAdminDatasourceToolkit::Utils::Collection).to have_received(:aggregate_relation) do
              |collection, id, relation_name, caller, foreign_filter, aggregation|
                expect(caller).to be_instance_of(Components::Caller)
                expect(collection.name).to eq('user')
                expect(id).to eq({ 'id' => 1 })
                expect(relation_name).to eq('category')
                expect(foreign_filter).to have_attributes(
                  condition_tree: have_attributes(aggregator: 'Or', conditions: []),
                  page: nil,
                  search: nil,
                  search_extended: nil,
                  segment: nil,
                  sort: nil
                )
                expect(aggregation).to be_instance_of(Components::Query::Aggregation)
                expect(aggregation).to have_attributes(operation: 'Count')
              end
            end
          end

          context 'when collection is not countable' do
            it 'return response without call aggregate_relation' do
              args[:params]['relation_name'] = 'category'
              args[:params]['id'] = 1
              args[:params][:filters] = JSON.generate({ field: 'id', operator: Operators::GREATER_THAN, value: 7 })
              allow(ForestAdminDatasourceToolkit::Utils::Collection).to receive(:aggregate_relation).and_return([])
              result = count.handle_request(args)

              expect(ForestAdminDatasourceToolkit::Utils::Collection).not_to have_received(:aggregate_relation)
              expect(result[:content]).to eq({ count: 'deactivated' })
            end
          end
        end
      end
    end
  end
end
