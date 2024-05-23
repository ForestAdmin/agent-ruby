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
        describe CsvRelated do
          include_context 'with caller'
          subject(:csv) { described_class.new }
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
          let(:csv_generator) { class_double(ForestAdminAgent::Utils::CsvGenerator).as_stubbed_const }

          before do
            user_class = Struct.new(:id, :first_name, :last_name, :category_id)
            stub_const('User', user_class)
            category_class = Struct.new(:id, :label)
            stub_const('Category', category_class)

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
              },
              list: [Category.new(1, 'bar'), Category.new(2, 'baz'), Category.new(3, 'qux')]
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

          it 'adds the route forest_related_list_csv' do
            csv.setup_routes
            expect(csv.routes.include?('forest_related_list_csv')).to be true
            expect(csv.routes.length).to eq 1
          end

          context 'when call csv' do
            # rubocop:disable RSpec/MultipleExpectations
            # rubocop:disable Metrics/ParameterLists
            it 'returns an export csv of the related collection' do
              args[:params]['relation_name'] = 'category'
              args[:params]['id'] = 1
              allow(ForestAdminDatasourceToolkit::Utils::Collection).to receive(:list_relation).and_return([Category.new(1, 'bar'), Category.new(2, 'baz'), Category.new(3, 'qux')])
              allow(csv_generator).to receive(:generate).with([Category.new(1, 'bar'), Category.new(2, 'baz'), Category.new(3, 'qux')], %w[id label]).and_return("id,label\n1,bar\n2,baz\n3,qux\n")
              result = csv.handle_request(args)

              expect(ForestAdminDatasourceToolkit::Utils::Collection).to have_received(:list_relation) do
              |collection, id, relation_name, caller, foreign_filter, projection|
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
                expect(projection).to eq(%w[id label])
              end

              expect(csv_generator).to have_received(:generate) do |records, projection|
                expect(records).to eq([Category.new(1, 'bar'), Category.new(2, 'baz'), Category.new(3, 'qux')])
                expect(projection).to eq(%w[id label])
              end
              expect(result[:filename]).to eq('category.csv')
              expect(result[:content][:export]).to eq("id,label\n1,bar\n2,baz\n3,qux\n")
            end
            # rubocop:enable RSpec/MultipleExpectations
            # rubocop:enable Metrics/ParameterLists

            it 'with a filename should return an export csv with the filename provided' do
              args[:params]['relation_name'] = 'category'
              args[:params]['id'] = 1
              args[:params][:filename] = 'filename'
              allow(ForestAdminDatasourceToolkit::Utils::Collection).to receive(:list_relation).and_return([Category.new(1, 'bar'), Category.new(2, 'baz'), Category.new(3, 'qux')])
              allow(csv_generator).to receive(:generate).with([Category.new(1, 'bar'), Category.new(2, 'baz'), Category.new(3, 'qux')], %w[id label]).and_return("id,label\n1,bar\n2,baz\n3,qux\n")
              result = csv.handle_request(args)

              expect(result[:filename]).to eq('filename.csv')
              expect(result[:content][:export]).to eq("id,label\n1,bar\n2,baz\n3,qux\n")
            end
          end
        end
      end
    end
  end
end
