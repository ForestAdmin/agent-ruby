module ForestAdminDatasourceMambuPayments
  include ForestAdminDatasourceToolkit::Components::Query

  Leaf = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

  RSpec.describe Collections::PayeeVerificationRequest do
    let(:client) { instance_double(ForestAdminDatasourceMambuPayments::Client) }
    let(:datasource) do
      instance_double(ForestAdminDatasourceMambuPayments::Datasource, client: client)
    end
    let(:collection) { described_class.new(datasource) }

    let(:payee_verification_request) do
      {
        'id' => 'pvr1', 'object' => 'payee_verification_request',
        'status' => 'completed', 'failure_code' => nil, 'status_details' => nil,
        'direction' => 'outgoing', 'scheme' => 'vop',
        'request' => {
          'payee_identification_type' => 'iban',
          'payee_identification' => 'BE68539007547034',
          'party_account_number' => 'BE68539007547034',
          'requesting_agent_bank_code' => 'DEUTDEFF',
          'responding_agent_bank_code' => 'GKCCBEBB'
        },
        'matching_result' => 'match',
        'payee_suggested_name' => nil,
        'matching_details' => {
          'cleaned_identification' => 'BE68539007547034',
          'matching_score' => 100
        },
        'scheme_data' => {
          'scheme_request_id' => 'scheme-1',
          'request_timestamp' => '2026-05-21T08:00:00Z',
          'response_timestamp' => '2026-05-21T08:00:30Z'
        },
        'metadata' => { 'src' => 'sandbox' },
        'response_received_at' => '2026-05-21T08:00:30Z',
        'created_at' => '2026-05-21T08:00:00Z'
      }
    end

    describe 'schema' do
      it 'declares the API-aligned columns' do
        keys = collection.schema[:fields].keys
        expect(keys).to include(
          'id', 'object', 'status', 'failure_code', 'status_details',
          'direction', 'scheme', 'request',
          'matching_result', 'payee_suggested_name',
          'matching_details', 'scheme_data', 'metadata',
          'response_received_at', 'created_at'
        )
      end

      it 'exposes status, failure_code, direction, scheme and matching_result as Enum columns' do
        f = collection.schema[:fields]
        expect(f['status'].column_type).to eq('Enum')
        expect(f['status'].enum_values).to contain_exactly('completed', 'failed')
        expect(f['failure_code'].enum_values)
          .to contain_exactly('business_error', 'technical_error', 'psp_technical_error')
        expect(f['direction'].enum_values).to contain_exactly('outgoing', 'incoming')
        expect(f['scheme'].enum_values).to contain_exactly('vop')
        expect(f['matching_result'].enum_values)
          .to contain_exactly('match', 'close_match', 'no_match', 'impossible_match')
      end

      it 'keeps request, matching_details, scheme_data and metadata as Json snapshots' do
        f = collection.schema[:fields]
        %w[request matching_details scheme_data metadata].each do |k|
          expect(f[k].column_type).to eq('Json'), "#{k} should be Json"
        end
      end

      it 'declares no ManyToOne relations (no top-level FK in Numeral payload)' do
        rels = collection.schema[:fields].select do |_, v|
          v.is_a?(ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema)
        end
        expect(rels).to be_empty
      end

      it 'marks every column as read-only (payee verification requests are bank/PSP-emitted)' do
        f = collection.schema[:fields]
        %w[id status failure_code direction scheme request matching_result
           matching_details scheme_data metadata response_received_at created_at].each do |k|
          expect(f[k].is_read_only).to be(true), "#{k} should be read-only"
        end
      end

      it 'does not implement create / update / delete' do
        expect(collection.public_methods(false)).not_to include(:create, :update, :delete)
      end
    end

    describe '#serialize' do
      it 'maps the API record to a flat hash with the schema fields' do
        result = collection.serialize(payee_verification_request)
        expect(result).to include(
          'id' => 'pvr1', 'status' => 'completed', 'direction' => 'outgoing',
          'scheme' => 'vop', 'matching_result' => 'match'
        )
      end

      it 'preserves nested objects as Json snapshots' do
        result = collection.serialize(payee_verification_request)
        expect(result['request']).to include('payee_identification' => 'BE68539007547034')
        expect(result['matching_details']).to include('matching_score' => 100)
        expect(result['scheme_data']).to include('scheme_request_id' => 'scheme-1')
      end
    end

    describe '#list' do
      it 'returns rows projected to the requested columns' do
        allow(client).to receive(:list_payee_verification_requests).and_return([payee_verification_request])

        rows = collection.list(nil, Filter.new, %w[id status matching_result])

        expect(rows).to eq([{ 'id' => 'pvr1', 'status' => 'completed', 'matching_result' => 'match' }])
      end

      it 'short-circuits to find_payee_verification_request on id lookup' do
        allow(client).to receive(:find_payee_verification_request)
          .with('pvr1').and_return(payee_verification_request)
        allow(client).to receive(:list_payee_verification_requests)

        filter = Filter.new(condition_tree: Leaf.new('id', 'equal', 'pvr1'))
        collection.list(nil, filter, nil)

        expect(client).to have_received(:find_payee_verification_request).with('pvr1')
        expect(client).not_to have_received(:list_payee_verification_requests)
      end

      it 'drops 404 (nil) records from the result on id lookup' do
        allow(client).to receive(:find_payee_verification_request).and_return(nil)
        filter = Filter.new(condition_tree: Leaf.new('id', 'in', %w[missing]))
        expect(collection.list(nil, filter, nil)).to eq([])
      end

      it 'forwards translated status, direction, scheme and matching_result filters to the API' do
        allow(client).to receive(:list_payee_verification_requests).and_return([])

        filter = Filter.new(condition_tree: Leaf.new('status', 'equal', 'failed'))
        collection.list(nil, filter, ['id'])
        expect(client).to have_received(:list_payee_verification_requests)
          .with(hash_including('status' => 'failed'))

        filter = Filter.new(condition_tree: Leaf.new('direction', 'equal', 'incoming'))
        collection.list(nil, filter, ['id'])
        expect(client).to have_received(:list_payee_verification_requests)
          .with(hash_including('direction' => 'incoming'))

        filter = Filter.new(condition_tree: Leaf.new('matching_result', 'equal', 'no_match'))
        collection.list(nil, filter, ['id'])
        expect(client).to have_received(:list_payee_verification_requests)
          .with(hash_including('matching_result' => 'no_match'))
      end

      it 'raises a clear error on an undeclared filter rather than silently dropping it' do
        allow(client).to receive(:list_payee_verification_requests)

        filter = Filter.new(condition_tree: Leaf.new('payee_suggested_name', 'equal', 'Alice'))

        expect { collection.list(nil, filter, ['id']) }
          .to raise_error(UnsupportedOperatorError, /'payee_suggested_name'/)
        expect(client).not_to have_received(:list_payee_verification_requests)
      end
    end

    describe '#aggregate Count' do
      it 'counts via list with a minimal projection' do
        allow(client).to receive(:list_payee_verification_requests)
          .and_return([payee_verification_request, payee_verification_request])
        result = collection.aggregate(nil, Filter.new, Aggregation.new(operation: 'Count'))
        expect(result.first['value']).to eq(2)
      end
    end
  end
end
