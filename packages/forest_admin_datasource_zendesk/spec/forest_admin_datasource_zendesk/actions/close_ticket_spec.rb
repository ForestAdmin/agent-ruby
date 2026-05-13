module ForestAdminDatasourceZendesk
  RSpec.describe Actions::CloseTicket do
    let(:client) { instance_double(ForestAdminDatasourceZendesk::Client) }
    let(:close_ticket_statuses) { [] }
    let(:datasource) do
      instance_double(ForestAdminDatasourceZendesk::Datasource,
                      client: client, custom_field_mapping: {},
                      close_ticket_statuses: close_ticket_statuses)
    end
    let(:result_builder) { ForestAdminDatasourceCustomizer::Decorators::Action::ResultBuilder.new }
    let(:action_scope) { ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope }

    describe '.variants' do
      it 'yields all four variants when both statuses are requested' do
        variants = described_class.variants(%w[solved closed])
        expect(variants.map { |name, _status, _scope| name }).to contain_exactly(
          'Mark as solved', 'Mark selected as solved',
          'Mark as closed', 'Mark selected as closed'
        )

        scopes = variants.each_with_object({}) { |(name, _status, scope), h| h[name] = scope }
        expect(scopes['Mark as solved']).to eq(action_scope::SINGLE)
        expect(scopes['Mark selected as solved']).to eq(action_scope::BULK)
        expect(scopes['Mark as closed']).to eq(action_scope::SINGLE)
        expect(scopes['Mark selected as closed']).to eq(action_scope::BULK)
      end

      it 'yields only the requested status variants (subset filtering)' do
        names = described_class.variants(%w[solved]).map(&:first)
        expect(names).to contain_exactly('Mark as solved', 'Mark selected as solved')
      end

      it 'yields nothing for an empty list' do
        expect(described_class.variants([])).to be_empty
      end

      it 'raises a ForestException on an unknown status' do
        expect { described_class.variants(%w[solved unknown]) }
          .to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException, /Unknown.*unknown/)
      end
    end

    describe 'executor' do
      let(:context) { Struct.new(:record_ids).new([42]) }

      it 'PUTs status=solved for the selected ticket id' do
        allow(client).to receive(:update_ticket)

        result = described_class.executor(datasource, 'solved').call(context, result_builder)

        expect(client).to have_received(:update_ticket).with(42, 'status' => 'solved')
        expect(result[:type]).to eq('Success')
        expect(result[:message]).to include('Ticket #42', 'marked as solved')
      end

      it 'PUTs status=closed for every id when run in bulk' do
        allow(client).to receive(:update_ticket)
        bulk_context = Struct.new(:record_ids).new([7, 8, 9])

        result = described_class.executor(datasource, 'closed').call(bulk_context, result_builder)

        [7, 8, 9].each { |id| expect(client).to have_received(:update_ticket).with(id, 'status' => 'closed') }
        expect(result[:message]).to include('3 tickets closed')
      end

      it 'returns an error and skips the API when no ids are present' do
        allow(client).to receive(:update_ticket)
        empty_context = Struct.new(:record_ids).new([])

        result = described_class.executor(datasource, 'solved').call(empty_context, result_builder)

        expect(client).not_to have_received(:update_ticket)
        expect(result[:type]).to eq('Error')
      end
    end

    describe 'integration with Ticket collection' do
      let(:ticket_collection) { Collections::Ticket.new(datasource) }
      let(:filter) do
        ForestAdminDatasourceToolkit::Components::Query::Filter.new(
          condition_tree: ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf.new(
            'id', 'equal', 42
          )
        )
      end

      it 'registers nothing by default (opt-in)' do
        action_keys = ticket_collection.schema[:actions].keys
        expect(action_keys).not_to include('Mark as solved', 'Mark as closed',
                                           'Mark selected as solved', 'Mark selected as closed')
      end

      context 'when close_ticket_statuses opts in to solved only' do
        let(:close_ticket_statuses) { %w[solved] }

        it 'registers only the solved variants' do
          keys = ticket_collection.schema[:actions].keys
          expect(keys).to include('Mark as solved', 'Mark selected as solved')
          expect(keys).not_to include('Mark as closed', 'Mark selected as closed')
        end
      end

      context 'when close_ticket_statuses opts in to both statuses' do
        let(:close_ticket_statuses) { %w[solved closed] }

        it 'wires the action through Collection#execute end-to-end' do
          allow(client).to receive(:fetch_tickets_by_ids).with([42]).and_return(42 => { 'id' => 42 })
          allow(client).to receive(:update_ticket)

          result = ticket_collection.execute(nil, 'Mark as solved', {}, filter)

          expect(client).to have_received(:update_ticket).with(42, 'status' => 'solved')
          expect(result[:type]).to eq('Success')
        end
      end
    end
  end
end
