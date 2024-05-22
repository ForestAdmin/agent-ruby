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
        describe ListRelated do
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
          let(:permissions) { instance_double(ForestAdminAgent::Services::Permissions) }

          before do
            user_class = Struct.new(:id, :first_name, :last_name, :category_id)
            stub_const('User', user_class)

            datasource = Datasource.new
            collection_user = collection_build(
              name: 'user',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                  'first_name' => ColumnSchema.new(column_type: 'String'),
                  'last_name' => ColumnSchema.new(column_type: 'String'),
                  'category_id' => ColumnSchema.new(column_type: 'Number'),
                  'category' => Relations::ManyToOneSchema.new(
                    foreign_key: 'category_id',
                    foreign_collection: 'category',
                    foreign_key_target: 'id'
                  )
                }
              },
              list: [User.new(1, 'foo', 'foo', 1)]
            )
            collection_category = collection_build(
              name: 'category',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                  'label' => ColumnSchema.new(column_type: 'String')
                }
              }
            )
            allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)
            datasource.add_collection(collection_user)
            datasource.add_collection(collection_category)
            ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(datasource)
            ForestAdminAgent::Builder::AgentFactory.instance.build

            @datasource = ForestAdminAgent::Facades::Container.datasource

            allow(ForestAdminAgent::Services::Permissions).to receive(:new).and_return(permissions)
            allow(permissions).to receive_messages(can?: true, get_scope: Nodes::ConditionTreeBranch.new('Or', []))
          end

          it 'adds the route forest_related_list' do
            list.setup_routes
            expect(list.routes.include?('forest_related_list')).to be true
            expect(list.routes.length).to eq 1
          end

          context 'when call without filters' do
            it 'call list_relation with expected args' do
              args[:params]['relation_name'] = 'category'
              args[:params]['id'] = 1
              allow(ForestAdminDatasourceToolkit::Utils::Collection).to receive(:list_relation).and_return([])
              list.handle_request(args)

              expect(ForestAdminDatasourceToolkit::Utils::Collection).to have_received(:list_relation) do
              |collection, id, relation_name, caller, foreign_filter, projection|
                expect(caller).to be_instance_of(Components::Caller)
                expect(collection.name).to eq('user')
                expect(id).to eq({ 'id' => 1 })
                expect(relation_name).to eq('category')
                expect(foreign_filter).to have_attributes(
                  condition_tree: have_attributes(aggregator: 'Or', conditions: []),
                  page: be_instance_of(ForestAdminDatasourceToolkit::Components::Query::Page),
                  search: nil,
                  search_extended: nil,
                  segment: nil,
                  sort: nil
                )
                expect(projection).to eq(%w[id label])
              end
            end
          end

          context 'when call with filters' do
            it 'call list_relation with expected args' do
              args[:params]['relation_name'] = 'category'
              args[:params]['id'] = 1
              args[:params][:filters] = JSON.generate({ field: 'id', operator: Operators::GREATER_THAN, value: 7 })
              allow(ForestAdminDatasourceToolkit::Utils::Collection).to receive(:list_relation).and_return([])
              list.handle_request(args)

              expect(ForestAdminDatasourceToolkit::Utils::Collection).to have_received(:list_relation) do
              |collection, id, relation_name, caller, foreign_filter, projection|
                expect(caller).to be_instance_of(Components::Caller)
                expect(collection.name).to eq('user')
                expect(id).to eq({ 'id' => 1 })
                expect(relation_name).to eq('category')
                expect(foreign_filter).to have_attributes(
                  condition_tree: have_attributes(
                    aggregator: 'And',
                    conditions: [
                      have_attributes(aggregator: 'Or', conditions: []),
                      have_attributes(field: 'id', operator: Operators::GREATER_THAN, value: 7)
                    ]
                  ),
                  page: be_instance_of(ForestAdminDatasourceToolkit::Components::Query::Page),
                  search: nil,
                  search_extended: nil,
                  segment: nil,
                  sort: nil
                )
                expect(projection).to eq(%w[id label])
              end
            end
          end
        end
      end
    end
  end
end
