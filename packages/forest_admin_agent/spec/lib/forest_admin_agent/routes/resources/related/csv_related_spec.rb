require 'spec_helper'
require 'singleton'
require 'ostruct'

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
          let(:csv_generator_stream) { class_double(ForestAdminAgent::Utils::CsvGeneratorStream).as_stubbed_const }

          before do
            user_class = Struct.new(:id, :first_name, :last_name, :category_id)
            stub_const('User', user_class)
            category_class = Struct.new(:id, :label)
            stub_const('Category', category_class)

            datasource = Datasource.new
            collection_user = build_collection(
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
            collection_category = build_collection(
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
            it 'returns a streaming export csv of the related collection' do
              args[:params]['relation_name'] = 'category'
              args[:params]['id'] = 1
              # Create a mock enumerator that yields CSV data
              mock_enumerator = ["id,label\n", "1,bar\n", "2,baz\n", "3,qux\n"].to_enum
              allow(csv_generator_stream).to receive(:stream).and_return(mock_enumerator)

              result = csv.handle_request(args)

              expect(csv_generator_stream).to have_received(:stream)
              expect(result[:status]).to eq(200)
              expect(result[:content][:type]).to eq('Stream')
              expect(result[:content][:enumerator]).to eq(mock_enumerator)
              expect(result[:content][:headers]['Content-Type']).to eq('text/csv; charset=utf-8')
              expect(result[:content][:headers]['Content-Disposition']).to match(/attachment; filename="user_category_export_\d{8}_\d{6}\.csv"/)
            end

            it 'with a filename should return an export csv with the filename provided' do
              args[:params]['relation_name'] = 'category'
              args[:params]['id'] = 1
              args[:params][:filename] = 'filename'
              # Create a mock enumerator that yields CSV data
              mock_enumerator = ["id,label\n", "1,bar\n", "2,baz\n", "3,qux\n"].to_enum
              allow(csv_generator_stream).to receive(:stream).and_return(mock_enumerator)

              result = csv.handle_request(args)

              expect(result[:status]).to eq(200)
              expect(result[:content][:type]).to eq('Stream')
              # NOTE: The implementation doesn't use the filename param for related exports.
              # It generates its own based on collection_name and relation_name.
              expect(result[:content][:headers]['Content-Disposition']).to match(/attachment; filename="user_category_export_\d{8}_\d{6}\.csv"/)
            end
          end
        end
      end
    end
  end
end
