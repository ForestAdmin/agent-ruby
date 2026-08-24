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
        include_context 'with readable related collections'
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

        it 'checks every query component it applies, against its own collection' do
          allow(csv_generator_stream).to receive(:stream).and_return([].to_enum)
          csv.handle_request(args)

          expect(read_guard_calls[:query_fields]).to eq(
            [{ collection: 'user', applies: %i[filter sort search] }]
          )
          expect(read_guard_calls[:projections]).to eq([{ collection: 'user', named_by_caller: false }])
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

          it 'exports the projection read from the Forest-Projection header, without adding the primary keys' do
            mock_enumerator = ["first_name\n", "foo\n"].to_enum
            allow(csv_generator_stream).to receive(:stream).and_return(mock_enumerator)

            args[:headers]['HTTP_FOREST_PROJECTION'] = 'first_name'
            args[:params][:fields] = { 'user' => 'last_name' }
            args[:params][:header] = 'First name'
            csv.handle_request(args)

            expect(csv_generator_stream).to have_received(:stream) do |header, _filter, projection, _list, _limit|
              expect(projection).to eq(%w[first_name])
              expect(header).to eq('First name')
            end
          end

          it 'does not fall back to the fields params when the header is invalid' do
            args[:headers]['HTTP_FOREST_PROJECTION'] = 'field-that-do-not-exist'
            args[:params][:fields] = { 'user' => 'last_name' }

            expect { csv.handle_request(args) }.to raise_error(
              Http::Exceptions::BadRequestError,
              /Invalid Forest-Projection header:/
            )
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
        end
      end
    end
  end
end
