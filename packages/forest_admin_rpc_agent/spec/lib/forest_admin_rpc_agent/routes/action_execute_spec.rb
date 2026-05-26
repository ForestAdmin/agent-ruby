require 'spec_helper'
require 'json'

module ForestAdminRpcAgent
  module Routes
    include ForestAdminDatasourceRpc
    include ForestAdminDatasourceToolkit::Components::Query
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

    describe ActionExecute do
      include_context 'with caller'
      subject(:route) { described_class.new }
      let(:collection_name) { 'users' }
      let(:filter) { ForestAdminDatasourceToolkit::Components::Query::Filter.new }
      let(:params) do
        {
          'collection_name' => 'users',
          'caller' => caller.to_h,
          'filter' => {},
          'data' => { 'field' => 'value' },
          'action' => 'some_action'
        }
      end
      let(:args) { { params: params } }
      let(:expected_response) { { success: true }.to_json }
      let(:response) do
        instance_double(Faraday::Response, success?: true, body: expected_response, status: 200,
                                           headers: {})
      end
      let(:faraday_connection) { instance_double(Faraday::Connection) }

      before do
        collection_schema = {
          name: collection_name,
          fields: {
            id: {
              column_type: 'Number',
              filter_operators: %w[present greater_than],
              is_primary_key: true,
              is_read_only: false,
              is_sortable: true,
              default_value: nil,
              enum_values: [],
              validation: [],
              type: 'Column'
            },
            email: {
              column_type: 'String',
              filter_operators: %w[in present i_contains contains],
              is_primary_key: false,
              is_read_only: false,
              is_sortable: true,
              default_value: nil,
              enum_values: [],
              validation: [],
              type: 'Column'
            }
          },
          countable: true,
          searchable: true,
          charts: [],
          segments: [],
          actions: {}
        }
        @datasource = ForestAdminDatasourceRpc::Datasource.new(
          {},
          { collections: [collection_schema], charts: [], rpc_relations: [] }
        )
        ForestAdminRpcAgent::Agent.instance.add_datasource(@datasource)
        ForestAdminRpcAgent::Agent.instance.build

        allow(ForestAdminDatasourceToolkit::Components::Query::FilterFactory)
          .to receive(:from_plain_object)
          .and_return(filter)
        allow(ForestAdminDatasourceToolkit::Components::Caller).to receive(:new).and_return(caller)

        allow(Faraday::Connection).to receive(:new).and_return(faraday_connection)
        allow(faraday_connection).to receive_messages(get: response, post: response)
      end

      describe '#handle_request' do
        context 'when collection_name is provided' do
          it 'executes the action on the collection and returns the response' do
            response = route.handle_request(args)
            expect(response).to eq(expected_response)
          end
        end

        context 'when the collection is unknown' do
          let(:params) { { 'collection_name' => 'unknown', 'action' => 'noop', 'data' => {} } }

          it 'raises NotFoundError so the controller maps it to a 404 response' do
            expect { route.handle_request(args) }
              .to raise_error(ForestAdminAgent::Http::Exceptions::NotFoundError)
          end
        end

        context 'when the action returns a File result' do
          let(:binary_payload) { String.new("%PDF-1.4\n%\xE2\xE3\xCF\xD3\n", encoding: 'ASCII-8BIT') }
          let(:file_result) do
            {
              type: 'File',
              name: 'report final.pdf',
              mime_type: 'application/pdf',
              stream: binary_payload,
              response_headers: { 'set-cookie' => 'token=xyz' }
            }
          end

          before do
            allow(@datasource.get_collection('users'))
              .to receive(:execute).and_return(file_result)
          end

          it 'returns a raw HTTP response so the binary content is not JSON-encoded' do
            response = route.handle_request(args)

            expect(response).to include(status: 200, raw: true)
            expect(response[:content]).to eq(binary_payload)
            expect(response[:content].encoding.name).to eq('ASCII-8BIT')
          end

          it 'sets File-specific headers including the encoded filename' do
            response = route.handle_request(args)
            headers = response[:headers]

            expect(headers['Content-Type']).to eq('application/pdf')
            expect(headers['X-Forest-Action-Type']).to eq('File')
            expect(headers['X-Forest-Action-File-Name']).to eq(CGI.escape('report final.pdf'))
            expect(headers['Content-Disposition']).to include(CGI.escape('report final.pdf'))
            expect(headers['X-Forest-Action-Response-Headers']).to eq({ 'set-cookie' => 'token=xyz' }.to_json)
          end

          context 'when the action does not provide response_headers' do
            let(:file_result) do
              { type: 'File', name: 'note.txt', mime_type: 'text/plain', stream: 'hi' }
            end

            it 'omits the X-Forest-Action-Response-Headers header' do
              response = route.handle_request(args)
              expect(response[:headers]).not_to have_key('X-Forest-Action-Response-Headers')
            end
          end
        end
      end
    end
  end
end
