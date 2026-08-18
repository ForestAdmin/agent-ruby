require 'spec_helper'

module ForestAdminAgent
  module Routes
    module Action
      include ForestAdminDatasourceToolkit::Schema
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

      describe Actions do
        subject(:route) { described_class.new(collection, 'Refund') }

        let(:action_scope) { ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope::BULK }
        let(:collection) do
          build_collection(
            name: 'orders',
            schema: {
              fields: {
                'id' => ColumnSchema.new(
                  column_type: 'Number', is_primary_key: true,
                  filter_operators: [Operators::IN, Operators::EQUAL]
                )
              },
              actions: { 'Refund' => double('action', scope: action_scope) }
            },
            list: [{ 'id' => 4 }, { 'id' => 7 }]
          )
        end
        let(:context) { double('context', collection: collection, caller: build_caller) }
        let(:filter) { ForestAdminDatasourceToolkit::Components::Query::Filter.new(condition_tree: nil) }

        describe 'the records it audits' do
          def audited_ids
            route.send(:audited_record_ids, context, filter)
          end

          # The ids a client sends are a claim. In a compliance record, asserting an operator acted on a record
          # their scope excludes is worse than a missing row, so the selection is read back through the caller's
          # own filter.
          it 'reads the targets back through the caller filter rather than trusting the request' do
            expect(audited_ids).to eq(%w[4 7])
            expect(collection).to have_received(:list) do |_caller, listed, projection|
              expect(listed.page.limit).to eq(ForestAdminAgent::AuditTrail::MAX_RECORDS_PER_OPERATION + 1)
              expect(projection).to eq(['id'])
            end
          end

          # Same rule as a bulk write: one unattached row for a run that touched more is a partial audit.
          it 'refuses a selection wider than the cap when critical is on' do
            allow(ForestAdminAgent::AuditTrail).to receive(:critical?).and_return(true)
            cap = ForestAdminAgent::AuditTrail::MAX_RECORDS_PER_OPERATION
            allow(collection).to receive(:list).and_return((1..(cap + 1)).map { |id| { 'id' => id } })

            expect { audited_ids }.to raise_error(
              ForestAdminDatasourceToolkit::Exceptions::ForestException, /cannot record an operation touching more/
            )
          end

          it 'records a selection wider than the cap as attached to no record, and says so' do
            logger = instance_spy(Services::LoggerService)
            allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(logger)
            cap = ForestAdminAgent::AuditTrail::MAX_RECORDS_PER_OPERATION
            allow(collection).to receive(:list).and_return((1..(cap + 1)).map { |id| { 'id' => id } })

            expect(audited_ids).to eq([])
            expect(logger).to have_received(:log).with('Warn', /records audited/)
          end

          context 'with a global action' do
            let(:action_scope) { ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope::GLOBAL }

            it 'names no record, and does not even query' do
              expect(audited_ids).to eq([])
              expect(collection).not_to have_received(:list)
            end
          end
        end

        describe 'auditing the run' do
          let(:store) { double('store', append_all: [10, 11], confirm: nil) }

          before do
            allow(ForestAdminAgent::Facades::Container).to receive(:config_from_cache)
              .and_return({ audit_trail: { store: store, redact: { 'orders' => ['reason'] } } })
          end

          def execute(result: { type: 'Success', message: 'done' }, &raising)
            allow(collection).to receive(:execute, &(raising || proc { result }))

            route.send(:execute_and_audit, context, {}, { 'amount' => 30, 'reason' => 'damaged' }, filter)
          end

          # Pending before the action, confirmed after: an action that takes the process down with it still
          # leaves evidence that it started.
          it 'records the run before it happens, one row per target' do
            execute

            expect(store).to have_received(:append_all) do |rows|
              expect(rows.map(&:record_id)).to eq(%w[4 7])
              expect(rows.map(&:status).uniq).to eq([ForestAdminAgent::AuditTrail::Recording::PENDING])
              expect(rows.first.action_name).to eq('Refund')
              expect(rows.first.previous_values).to eq({ 'amount' => 30, 'reason' => '[redacted]' })
            end
          end

          it 'confirms both rows with what the action answered, and returns it' do
            expect(execute).to eq({ type: 'Success', message: 'done' })

            expect(store).to have_received(:confirm).with(
              10, hash_including(operation: 'action', new_values: { 'type' => 'Success', 'message' => 'done' })
            )
            expect(store).to have_received(:confirm).with(11, any_args)
          end

          it 'confirms as failed and re-raises when the action raises' do
            expect { execute { raise StandardError, 'boom' } }.to raise_error(StandardError, 'boom')

            expect(store).to have_received(:confirm).with(10, hash_including(operation: 'action_failed'))
          end

          it 'confirms as failed when the action answers with an Error result' do
            execute(result: { type: 'Error', message: 'not allowed' })

            expect(store).to have_received(:confirm).with(10, hash_including(operation: 'action_failed'))
          end

          it 'does nothing at all without an audit database, not even reading the selection' do
            allow(ForestAdminAgent::Facades::Container).to receive(:config_from_cache).and_return({})

            expect(execute).to eq({ type: 'Success', message: 'done' })
            expect(collection).not_to have_received(:list)
            expect(store).not_to have_received(:append_all)
          end

          # The action has not run yet, so refusing costs nothing to repair — but only when asked to.
          it 'refuses the action when the pending row cannot be written and critical is on' do
            allow(ForestAdminAgent::AuditTrail).to receive(:critical?).and_return(true)
            allow(store).to receive(:append_all).and_raise(StandardError, 'audit db is down')

            expect { execute }.to raise_error(StandardError, 'audit db is down')
            expect(collection).not_to have_received(:execute)
          end

          it 'runs the action anyway when the pending row cannot be written and critical is off' do
            logger = instance_spy(Services::LoggerService)
            allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(logger)
            allow(store).to receive(:append_all).and_raise(StandardError, 'audit db is down')

            expect(execute).to eq({ type: 'Success', message: 'done' })
            expect(logger).to have_received(:log).with('Error', /audit db is down/)
          end

          # Reading the selection happens inside the gate too, so a failure there cannot 500 an action.
          it 'runs the action anyway when the selection cannot be read' do
            allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(
              instance_spy(Services::LoggerService)
            )
            allow(collection).to receive(:list).and_raise(StandardError, 'datasource down')

            expect(execute).to eq({ type: 'Success', message: 'done' })
          end
        end
      end
    end
  end
end
