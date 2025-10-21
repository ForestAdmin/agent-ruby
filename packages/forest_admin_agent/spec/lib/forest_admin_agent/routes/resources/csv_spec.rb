require 'spec_helper'
require 'singleton'
require 'ostruct'

require 'json'

module ForestAdminAgent
  module Routes
    module Resources
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminDatasourceToolkit::Schema
      describe Csv do
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
          user_class = Struct.new(:id, :first_name, :last_name)
          stub_const('User', user_class)

          datasource = Datasource.new
          collection = build_collection(
            name: 'user',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'first_name' => ColumnSchema.new(column_type: 'String'),
                'last_name' => ColumnSchema.new(column_type: 'String')
              }
            },
            list: [User.new(1, 'foo', 'foo')]
          )

          allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)
          datasource.add_collection(collection)
          ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(datasource)
          ForestAdminAgent::Builder::AgentFactory.instance.build
          @datasource = ForestAdminAgent::Facades::Container.datasource
          allow(@datasource.get_collection('user')).to receive(:list).and_return([User.new(1, 'foo', 'foo')])

          allow(ForestAdminAgent::Services::Permissions).to receive(:new).and_return(permissions)
          allow(permissions).to receive_messages(can?: true, get_scope: nil)
        end

        it 'adds the route forest_list_csv' do
          csv.setup_routes
          expect(csv.routes.include?('forest_list_csv')).to be true
          expect(csv.routes.length).to eq 1
        end

        context 'when call csv' do
          it 'returns a streaming export csv' do
            # Create a mock enumerator that yields CSV data
            mock_enumerator = ["id,first_name,last_name\n", "1,foo,foo\n"].to_enum
            allow(csv_generator_stream).to receive(:stream).and_return(mock_enumerator)

            result = csv.handle_request(args)

            expect(csv_generator_stream).to have_received(:stream)
            expect(result[:status]).to eq(200)
            expect(result[:content][:type]).to eq('Stream')
            expect(result[:content][:enumerator]).to eq(mock_enumerator)
            expect(result[:content][:headers]['Content-Type']).to eq('text/csv; charset=utf-8')
            expect(result[:content][:headers]['Content-Disposition']).to match(/attachment; filename="user_export_\d{8}_\d{6}\.csv"/)
          end

          it 'with a filename should return an export csv with the filename provided' do
            mock_enumerator = ["id,first_name,last_name\n", "1,foo,foo\n"].to_enum
            allow(csv_generator_stream).to receive(:stream).and_return(mock_enumerator)

            args[:params][:filename] = 'filename'
            result = csv.handle_request(args)

            expect(result[:status]).to eq(200)
            expect(result[:content][:type]).to eq('Stream')
            expect(result[:content][:headers]['Content-Disposition']).to match(/attachment; filename="filename_export_\d{8}_\d{6}\.csv"/)
          end

          it 'actually streams CSV data using the real CsvGeneratorStream' do
            # Don't stub CsvGeneratorStream - let it use the real implementation
            args[:params][:header] = '["id","first_name","last_name"]'

            result = csv.handle_request(args)

            # Get the enumerator and consume it
            enumerator = result[:content][:enumerator]
            csv_output = enumerator.to_a.join

            # Verify the CSV output
            expect(csv_output).to include('id,first_name,last_name')
            expect(csv_output).to include('1,foo,foo')
            expect(result[:status]).to eq(200)
            expect(result[:content][:type]).to eq('Stream')
          end

          it 'streams multiple records in batches' do
            # Create multiple users
            users = (1..5).map { |i| User.new(i, "first_#{i}", "last_#{i}") }
            allow(@datasource.get_collection('user')).to receive(:list).and_return(users)

            args[:params][:header] = '["id","first_name","last_name"]'

            result = csv.handle_request(args)
            enumerator = result[:content][:enumerator]
            csv_output = enumerator.to_a.join

            # Verify all records are present
            expect(csv_output).to include('id,first_name,last_name')
            (1..5).each do |i|
              expect(csv_output).to include("#{i},first_#{i},last_#{i}")
            end
          end

          it 'handles empty result set' do
            allow(@datasource.get_collection('user')).to receive(:list).and_return([])

            args[:params][:header] = '["id","first_name","last_name"]'

            result = csv.handle_request(args)
            enumerator = result[:content][:enumerator]
            csv_output = enumerator.to_a.join

            # Should only have header
            lines = csv_output.split("\n")
            expect(lines.length).to eq(1)
            expect(lines[0]).to include('id,first_name,last_name')
          end
        end
      end
    end
  end
end
