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

  RSpec.describe Plugins::CloseTicket do
    let(:client) { instance_double(ForestAdminDatasourceZendesk::Client) }
    let(:datasource) do
      instance_double(ForestAdminDatasourceZendesk::Datasource, client: client, custom_field_mapping: {})
    end
    let(:result_builder) { ForestAdminDatasourceCustomizer::Decorators::Action::ResultBuilder.new }
    let(:action_scope) { ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope }
    let(:ticket_id_field) { 'last_zendesk_ticket_id' }
    let(:collection_customizer) do
      Class.new do
        attr_reader :registered

        def initialize = @registered = {}
        def add_action(name, action) = @registered[name] = action
      end.new
    end

    def register(opts = {})
      described_class.new.run(nil, collection_customizer,
                              { datasource: datasource, ticket_id_field: ticket_id_field }.merge(opts))
      collection_customizer.registered
    end

    describe '#run' do
      it 'registers all four variants by default (solved/closed × single/bulk)' do
        register

        expect(collection_customizer.registered.keys).to contain_exactly(
          'Mark Zendesk ticket as solved', 'Mark selected Zendesk tickets as solved',
          'Mark Zendesk ticket as closed', 'Mark selected Zendesk tickets as closed'
        )
      end

      it 'honors :statuses to keep only the requested status family' do
        register(statuses: %w[solved])
        expect(collection_customizer.registered.keys).to contain_exactly(
          'Mark Zendesk ticket as solved', 'Mark selected Zendesk tickets as solved'
        )
      end

      it 'honors :scopes to keep only the requested scopes' do
        register(scopes: %i[single])
        expect(collection_customizer.registered.keys).to contain_exactly(
          'Mark Zendesk ticket as solved', 'Mark Zendesk ticket as closed'
        )
      end

      it 'composes both :statuses and :scopes to a Cartesian subset (one action)' do
        register(statuses: %w[closed], scopes: %i[bulk])
        expect(collection_customizer.registered.keys).to contain_exactly('Mark selected Zendesk tickets as closed')
      end

      it 'accepts symbol statuses and string scopes interchangeably' do
        register(statuses: %i[solved], scopes: %w[bulk])
        expect(collection_customizer.registered.keys).to contain_exactly('Mark selected Zendesk tickets as solved')
      end

      it 'binds the right ActionScope to each registered action' do
        register
        registered = collection_customizer.registered
        expect(registered['Mark Zendesk ticket as solved'].scope).to eq(action_scope::SINGLE)
        expect(registered['Mark selected Zendesk tickets as solved'].scope).to eq(action_scope::BULK)
        expect(registered['Mark Zendesk ticket as closed'].scope).to eq(action_scope::SINGLE)
        expect(registered['Mark selected Zendesk tickets as closed'].scope).to eq(action_scope::BULK)
      end

      it 'raises a ForestException on an unknown status' do
        expect { register(statuses: %w[solved unknown]) }
          .to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException, /Unknown.*unknown/)
      end

      it 'raises a ForestException on an unknown scope' do
        expect { register(scopes: %i[single weird]) }
          .to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException, /Unknown.*weird/)
      end

      it 'raises ArgumentError without :datasource' do
        expect { described_class.new.run(nil, collection_customizer, ticket_id_field: 'id') }
          .to raise_error(ArgumentError, /datasource/)
      end

      it 'raises ArgumentError without :ticket_id_field' do
        expect { described_class.new.run(nil, collection_customizer, datasource: datasource) }
          .to raise_error(ArgumentError, /ticket_id_field/)
      end

      it 'raises ArgumentError without a collection_customizer' do
        expect do
          described_class.new.run(nil, nil, datasource: datasource, ticket_id_field: 'id')
        end.to raise_error(ArgumentError, /collection/)
      end
    end

    describe 'executor' do
      let(:solved_single) do
        register(statuses: %w[solved], scopes: %i[single])['Mark Zendesk ticket as solved']
      end
      let(:closed_bulk) do
        register(statuses: %w[closed], scopes: %i[bulk])['Mark selected Zendesk tickets as closed']
      end

      it 'reads the ticket id from the host field and PUTs status=solved' do
        allow(client).to receive(:update_ticket)
        context = FakeCloseContext.new(records: [{ ticket_id_field => 42 }])

        result = solved_single.execute.call(context, result_builder)

        expect(client).to have_received(:update_ticket).with(42, 'status' => 'solved')
        expect(result[:type]).to eq('Success')
        expect(result[:message]).to include('Ticket #42', 'marked as solved')
      end

      it 'PUTs status=closed for every host record when run in bulk' do
        allow(client).to receive(:update_ticket)
        bulk_context = FakeCloseContext.new(
          records: [7, 8, 9].map { |id| { ticket_id_field => id } }
        )

        result = closed_bulk.execute.call(bulk_context, result_builder)

        [7, 8, 9].each { |id| expect(client).to have_received(:update_ticket).with(id, 'status' => 'closed') }
        expect(result[:message]).to include('3 tickets closed')
      end

      it 'returns an error when no host record carries a ticket id' do
        allow(client).to receive(:update_ticket)
        context = FakeCloseContext.new(records: [{ ticket_id_field => nil }])

        result = solved_single.execute.call(context, result_builder)

        expect(client).not_to have_received(:update_ticket)
        expect(result[:type]).to eq('Error')
        expect(result[:message]).to include(ticket_id_field)
      end

      it 'works with symbol keys on the host record' do
        allow(client).to receive(:update_ticket)
        context = FakeCloseContext.new(records: [{ ticket_id_field.to_sym => 99 }])

        solved_single.execute.call(context, result_builder)

        expect(client).to have_received(:update_ticket).with(99, 'status' => 'solved')
      end

      context 'when Zendesk rejects some ids (partial success on bulk)' do
        let(:bulk_context) do
          FakeCloseContext.new(records: [7, 8, 9].map { |id| { ticket_id_field => id } })
        end

        it 'continues with the remaining ids and surfaces the failures in the message' do
          allow(client).to receive(:update_ticket)
            .with(8, anything).and_raise(StandardError, 'cannot transition open to closed')
          allow(client).to receive(:update_ticket).with(7, anything)
          allow(client).to receive(:update_ticket).with(9, anything)
          allow(ForestAdminDatasourceZendesk.logger).to receive(:warn)

          result = closed_bulk.execute.call(bulk_context, result_builder)

          expect(result[:type]).to eq('Success')
          expect(result[:message]).to include('2 tickets closed', '1 failed', '8')
          expect(ForestAdminDatasourceZendesk.logger).to have_received(:warn)
            .with(a_string_including('#8', 'cannot transition'))
        end

        it 'returns an Error when every id fails' do
          allow(client).to receive(:update_ticket).and_raise(StandardError, 'permission denied')
          allow(ForestAdminDatasourceZendesk.logger).to receive(:warn).exactly(3).times

          result = closed_bulk.execute.call(bulk_context, result_builder)

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

          result = solved_single.execute.call(context, result_builder)

          expect(client).not_to have_received(:update_ticket)
          expect(result[:type]).to eq('Error')
          expect(ForestAdminDatasourceZendesk.logger).to have_received(:warn)
            .with(a_string_including(ticket_id_field, 'boom'))
        end
      end
    end

    describe "Zendesk's 'closed prevents ticket update' error" do
      let(:already_closed_error) do
        StandardError.new(
          'Zendesk API call failed: update(tickets/254): ZendeskAPI::Error::RecordInvalid: ' \
          '{"status" => [{"description" => "closed prevents ticket update"}]}'
        )
      end
      let(:solved_single) do
        register(statuses: %w[solved], scopes: %i[single])['Mark Zendesk ticket as solved']
      end
      let(:closed_single) do
        register(statuses: %w[closed], scopes: %i[single])['Mark Zendesk ticket as closed']
      end
      let(:closed_bulk) do
        register(statuses: %w[closed], scopes: %i[bulk])['Mark selected Zendesk tickets as closed']
      end

      it "with status='closed' on an already-closed ticket: clean Success ('was already closed')" do
        allow(client).to receive(:update_ticket).and_raise(already_closed_error)
        allow(ForestAdminDatasourceZendesk.logger).to receive(:warn)
        context = FakeCloseContext.new(records: [{ ticket_id_field => 254 }])

        result = closed_single.execute.call(context, result_builder)

        expect(result[:type]).to eq('Success')
        expect(result[:message]).to eq('Ticket #254 was already closed.')
        # No warn log: an idempotent "already closed" is an expected state.
        expect(ForestAdminDatasourceZendesk.logger).not_to have_received(:warn)
      end

      it "with status='closed' in bulk: mixes succeeded + already-closed + other failures cleanly" do
        allow(client).to receive(:update_ticket).with(7, anything)
        allow(client).to receive(:update_ticket).with(8, anything).and_raise(already_closed_error)
        allow(client).to receive(:update_ticket).with(9, anything).and_raise(StandardError, 'permission denied')
        allow(ForestAdminDatasourceZendesk.logger).to receive(:warn)
        context = FakeCloseContext.new(records: [7, 8, 9].map { |id| { ticket_id_field => id } })

        result = closed_bulk.execute.call(context, result_builder)

        expect(result[:type]).to eq('Success')
        expect(result[:message]).to include('Ticket #7 closed.', 'Ticket #8 was already closed.', '1 failed: 9')
        # Only the genuine failure is logged; "already closed" stays quiet.
        expect(ForestAdminDatasourceZendesk.logger).to have_received(:warn)
          .with(a_string_including('#9', 'permission denied'))
        expect(ForestAdminDatasourceZendesk.logger).not_to have_received(:warn)
          .with(a_string_including('#8'))
      end

      it "with status='solved' on an already-closed ticket: Error explaining it can't be reopened" do
        allow(client).to receive(:update_ticket).and_raise(already_closed_error)
        context = FakeCloseContext.new(records: [{ ticket_id_field => 254 }])

        result = solved_single.execute.call(context, result_builder)

        expect(result[:type]).to eq('Error')
        expect(result[:message]).to include('#254', 'already closed', 'cannot reopen')
        # Make sure the raw API stack is gone.
        expect(result[:message]).not_to include('RecordInvalid')
        expect(result[:message]).not_to include('"description"')
      end
    end
  end
end
