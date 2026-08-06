require 'spec_helper'

module ForestAdminDatasourceGraphqlHasura
  RSpec.describe Client do
    let(:configuration) { Configuration.new(uri: BankingSchema::GRAPHQL_URI) }
    let(:client) { described_class.new(configuration) }

    describe '#execute' do
      it 'returns the data payload' do
        WebMock.stub_request(:post, BankingSchema::GRAPHQL_URI)
               .to_return(status: 200, body: JSON.generate({ 'data' => { 'ok' => 1 } }))

        expect(client.execute('query { ok }')).to eq({ 'ok' => 1 })
      end

      it 'sends the configured headers' do
        configuration = Configuration.new(uri: BankingSchema::GRAPHQL_URI,
                                          headers: { 'x-hasura-admin-secret' => 's3cret' })
        stub = WebMock.stub_request(:post, BankingSchema::GRAPHQL_URI)
                      .with(headers: { 'x-hasura-admin-secret' => 's3cret' })
                      .to_return(status: 200, body: JSON.generate({ 'data' => {} }))

        described_class.new(configuration).execute('query { ok }')

        expect(stub).to have_been_requested
      end

      # Errors Hasura itself returns are the user's to act on: 400.
      it 'raises GraphqlError carrying every message Hasura returns' do
        WebMock.stub_request(:post, BankingSchema::GRAPHQL_URI)
               .to_return(status: 200,
                          body: JSON.generate({ 'errors' => [{ 'message' => 'permission denied' },
                                                             { 'message' => 'field unknown' }] }))

        expect { client.execute('query { ok }') }
          .to raise_error(GraphqlError, 'permission denied; field unknown')
      end

      # Infrastructure failures are not client mistakes: 503, message kept.
      it 'raises TransportError with a 503 status on a non-2xx response' do
        WebMock.stub_request(:post, BankingSchema::GRAPHQL_URI).to_return(status: 502, body: 'bad gateway')

        expect { client.execute('query { ok }') }.to raise_error(TransportError) do |error|
          expect(error.status).to eq(503)
          expect(error.message).to include('HTTP 502')
        end
      end

      it 'raises TransportError on a timeout' do
        WebMock.stub_request(:post, BankingSchema::GRAPHQL_URI).to_timeout

        expect { client.execute('query { ok }') }.to raise_error(TransportError, /Could not reach/)
      end

      it 'raises TransportError on a connection failure' do
        WebMock.stub_request(:post, BankingSchema::GRAPHQL_URI).to_raise(SocketError.new('getaddrinfo failed'))

        expect { client.execute('query { ok }') }
          .to raise_error(TransportError, /getaddrinfo failed/)
      end

      it 'raises TransportError on a body that is not JSON' do
        WebMock.stub_request(:post, BankingSchema::GRAPHQL_URI).to_return(status: 200, body: '<html>oops</html>')

        expect { client.execute('query { ok }') }.to raise_error(TransportError, /Could not reach/)
      end

      it 'raises TransportError on a JSON body that is not an object' do
        WebMock.stub_request(:post, BankingSchema::GRAPHQL_URI).to_return(status: 200, body: '[]')

        expect { client.execute('query { ok }') }.to raise_error(TransportError, /unexpected body/)
      end

      # A 204 passes the Net::HTTPSuccess check with a nil body, which
      # JSON.parse would turn into an unwrapped TypeError.
      it 'raises TransportError on an empty body' do
        WebMock.stub_request(:post, BankingSchema::GRAPHQL_URI).to_return(status: 204, body: nil)

        expect { client.execute('query { ok }') }.to raise_error(TransportError, /empty body/)
      end

      it 'raises TransportError on a 200 carrying neither data nor errors' do
        WebMock.stub_request(:post, BankingSchema::GRAPHQL_URI)
               .to_return(status: 200, body: JSON.generate({ 'data' => nil }))

        expect { client.execute('query { ok }') }.to raise_error(TransportError, /no data/)
      end
    end

    describe 'configuration' do
      it 'treats an explicit nil option as the default' do
        configuration = Configuration.new(uri: BankingSchema::GRAPHQL_URI, headers: nil)
        WebMock.stub_request(:post, BankingSchema::GRAPHQL_URI)
               .to_return(status: 200, body: JSON.generate({ 'data' => {} }))

        expect(described_class.new(configuration).execute('query { ok }')).to eq({})
      end

      it 'does not share default objects across instances' do
        first = Configuration.new(uri: BankingSchema::GRAPHQL_URI)
        second = Configuration.new(uri: BankingSchema::GRAPHQL_URI)
        first.headers['Authorization'] = 'leak'

        expect(second.headers).to eq({})
      end

      # A String would silently become a substring check instead of a name match.
      it 'rejects table lists that are not arrays by name' do
        expect do
          Configuration.new(uri: BankingSchema::GRAPHQL_URI, included_tables: 'users')
        end.to raise_error(ConfigurationError, /must be arrays/)
      end

      it 'rejects a misshapen polymorphic_relations declaration by name' do
        expect do
          Configuration.new(uri: BankingSchema::GRAPHQL_URI,
                            polymorphic_relations: { 'comments' => ['commentable'] })
        end.to raise_error(ConfigurationError, /polymorphic_relations/)
      end
    end

    describe '#fetch_metadata' do
      it 'returns the metadata when the endpoint answers' do
        WebMock.stub_request(:post, BankingSchema::METADATA_URI)
               .to_return(status: 200, body: JSON.generate({ 'metadata' => { 'sources' => [] } }))

        expect(client.fetch_metadata).to eq({ 'sources' => [] })
      end

      it 'returns nil when the endpoint is forbidden' do
        WebMock.stub_request(:post, BankingSchema::METADATA_URI).to_return(status: 403, body: '{}')

        expect(client.fetch_metadata).to be_nil
      end

      # An uri without the conventional segment yields no derivable metadata
      # endpoint: introspection must not post metadata commands to GraphQL.
      it 'skips the call entirely when no metadata endpoint could be derived' do
        configuration = Configuration.new(uri: 'http://hasura.test/custom-graphql')

        expect(described_class.new(configuration).fetch_metadata).to be_nil
        expect(WebMock).not_to have_requested(:post, 'http://hasura.test/custom-graphql')
      end
    end
  end
end
