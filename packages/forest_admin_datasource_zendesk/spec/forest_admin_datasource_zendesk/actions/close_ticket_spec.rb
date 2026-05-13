module ForestAdminDatasourceZendesk
  # Stand-in for an action context. The executor only reads
  # `get_records(fields)` so we don't need the full ActionContext class here.
  class FakeCloseContext
    def initialize(records: [])
      @records = records
    end

    def get_records(_fields = [])
      @records
    end
  end

  RSpec.describe Actions::CloseTicket do
    let(:client) { instance_double(ForestAdminDatasourceZendesk::Client) }
    let(:datasource) do
      instance_double(ForestAdminDatasourceZendesk::Datasource, client: client, custom_field_mapping: {})
    end
    let(:result_builder) { ForestAdminDatasourceCustomizer::Decorators::Action::ResultBuilder.new }
    let(:action_scope) { ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope }
    let(:ticket_id_field) { 'last_zendesk_ticket_id' }

    describe '.variants' do
      it 'yields all four variants when both statuses are requested' do
        variants = described_class.variants(%w[solved closed])
        expect(variants.map { |name, _status, _scope| name }).to contain_exactly(
          'Mark Zendesk ticket as solved', 'Mark selected Zendesk tickets as solved',
          'Mark Zendesk ticket as closed', 'Mark selected Zendesk tickets as closed'
        )

        scopes = variants.each_with_object({}) { |(name, _status, scope), h| h[name] = scope }
        expect(scopes['Mark Zendesk ticket as solved']).to eq(action_scope::SINGLE)
        expect(scopes['Mark selected Zendesk tickets as solved']).to eq(action_scope::BULK)
        expect(scopes['Mark Zendesk ticket as closed']).to eq(action_scope::SINGLE)
        expect(scopes['Mark selected Zendesk tickets as closed']).to eq(action_scope::BULK)
      end

      it 'yields only the requested status variants (subset filtering)' do
        names = described_class.variants(%w[solved]).map(&:first)
        expect(names).to contain_exactly('Mark Zendesk ticket as solved', 'Mark selected Zendesk tickets as solved')
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
      let(:executor) { described_class.executor(datasource, 'solved', ticket_id_field) }

      it 'reads the ticket id from the host field and PUTs status=solved' do
        allow(client).to receive(:update_ticket)
        context = FakeCloseContext.new(records: [{ ticket_id_field => 42 }])

        result = executor.call(context, result_builder)

        expect(client).to have_received(:update_ticket).with(42, 'status' => 'solved')
        expect(result[:type]).to eq('Success')
        expect(result[:message]).to include('Ticket #42', 'marked as solved')
      end

      it 'PUTs status=closed for every host record when run in bulk' do
        allow(client).to receive(:update_ticket)
        bulk_executor = described_class.executor(datasource, 'closed', ticket_id_field)
        bulk_context = FakeCloseContext.new(
          records: [7, 8, 9].map { |id| { ticket_id_field => id } }
        )

        result = bulk_executor.call(bulk_context, result_builder)

        [7, 8, 9].each { |id| expect(client).to have_received(:update_ticket).with(id, 'status' => 'closed') }
        expect(result[:message]).to include('3 tickets closed')
      end

      it 'returns an error when no host record carries a ticket id' do
        allow(client).to receive(:update_ticket)
        context = FakeCloseContext.new(records: [{ ticket_id_field => nil }])

        result = executor.call(context, result_builder)

        expect(client).not_to have_received(:update_ticket)
        expect(result[:type]).to eq('Error')
        expect(result[:message]).to include(ticket_id_field)
      end

      it 'works with symbol keys on the host record' do
        allow(client).to receive(:update_ticket)
        context = FakeCloseContext.new(records: [{ ticket_id_field.to_sym => 99 }])

        executor.call(context, result_builder)

        expect(client).to have_received(:update_ticket).with(99, 'status' => 'solved')
      end

      context 'when Zendesk rejects some ids (partial success on bulk)' do
        let(:bulk_executor) { described_class.executor(datasource, 'closed', ticket_id_field) }
        let(:bulk_context) do
          FakeCloseContext.new(records: [7, 8, 9].map { |id| { ticket_id_field => id } })
        end

        it 'continues with the remaining ids and surfaces the failures in the message' do
          allow(client).to receive(:update_ticket)
            .with(8, anything).and_raise(StandardError, 'cannot transition open to closed')
          allow(client).to receive(:update_ticket).with(7, anything)
          allow(client).to receive(:update_ticket).with(9, anything)
          allow(ForestAdminDatasourceZendesk.logger).to receive(:warn)

          result = bulk_executor.call(bulk_context, result_builder)

          expect(result[:type]).to eq('Success')
          expect(result[:message]).to include('2 tickets closed', '1 failed', '8')
          expect(ForestAdminDatasourceZendesk.logger).to have_received(:warn)
            .with(a_string_including('#8', 'cannot transition'))
        end

        it 'returns an Error when every id fails' do
          allow(client).to receive(:update_ticket).and_raise(StandardError, 'permission denied')
          allow(ForestAdminDatasourceZendesk.logger).to receive(:warn).exactly(3).times

          result = bulk_executor.call(bulk_context, result_builder)

          expect(result[:type]).to eq('Error')
          expect(result[:message]).to include('Failed to close', '3 tickets', 'permission denied')
        end
      end

      context 'when get_records itself raises' do
        it 'logs and returns an Error message without calling the client' do
          context = instance_double(
            ForestAdminDatasourceCustomizer::Decorators::Action::Context::ActionContextSingle
          )
          allow(context).to receive(:get_records).and_raise(StandardError, 'boom')
          allow(ForestAdminDatasourceZendesk.logger).to receive(:warn)
          allow(client).to receive(:update_ticket)

          result = executor.call(context, result_builder)

          expect(client).not_to have_received(:update_ticket)
          expect(result[:type]).to eq('Error')
          expect(ForestAdminDatasourceZendesk.logger).to have_received(:warn)
            .with(a_string_including(ticket_id_field, 'boom'))
        end
      end
    end

    describe '.register_on' do
      let(:host_collection) do
        Class.new do
          attr_reader :registered

          def initialize = @registered = {}
          def add_action(name, action) = @registered[name] = action
        end.new
      end

      it 'registers the four variants on an arbitrary host collection' do
        described_class.register_on(host_collection, datasource, ticket_id_field: ticket_id_field)

        expect(host_collection.registered.keys).to contain_exactly(
          'Mark Zendesk ticket as solved', 'Mark selected Zendesk tickets as solved',
          'Mark Zendesk ticket as closed', 'Mark selected Zendesk tickets as closed'
        )
      end

      it 'registers only the subset specified via :statuses' do
        described_class.register_on(host_collection, datasource,
                                    ticket_id_field: ticket_id_field, statuses: %w[solved])

        expect(host_collection.registered.keys).to contain_exactly(
          'Mark Zendesk ticket as solved', 'Mark selected Zendesk tickets as solved'
        )
      end
    end
  end
end
