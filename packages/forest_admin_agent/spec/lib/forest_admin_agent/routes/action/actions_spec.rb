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
            }
          )
        end
        let(:context) { double('context', collection: collection) }

        def audited_ids(attributes)
          route.send(:audited_record_ids, { params: { data: { attributes: attributes } } }, context)
        end

        it 'packs the ids of an explicit selection' do
          expect(audited_ids({ ids: %w[4 7] })).to eq(%w[4 7])
        end

        # A select-all selection only carries the excluded ids: naming the targets would mean querying
        # the whole selection, so the run is recorded unattached instead.
        it 'returns no id for a select-all selection' do
          expect(audited_ids({ ids: ['4'], all_records: true, all_records_ids_excluded: ['9'] })).to eq([])
        end

        describe 'auditing the run' do
          let(:store) { double('store', append: nil) }
          let(:context) { double('context', collection: collection, caller: build_caller) }
          let(:args) { { params: { data: { attributes: { ids: %w[4 7] } } } } }

          before do
            allow(ForestAdminAgent::Facades::Container).to receive(:config_from_cache)
              .and_return({ audit_trail: { store: store, redact: { 'orders' => ['reason'] } } })
          end

          def execute(result: { type: 'Success', message: 'done' }, &raising)
            allow(collection).to receive(:execute, &(raising || proc { result }))
            route.send(:execute_and_audit, context, args, { 'amount' => 30, 'reason' => 'damaged' }, nil)
          end

          it 'records one row per selected record and returns the action result' do
            expect(execute).to eq({ type: 'Success', message: 'done' })

            expect(store).to have_received(:append).twice
            expect(store).to have_received(:append).with(
              having_attributes(operation: 'action', collection: 'orders', record_id: '4',
                                new_values: { 'amount' => 30, 'reason' => '[redacted]' })
            )
          end

          it 'records the attempt and re-raises when the action fails' do
            expect { execute { raise StandardError, 'boom' } }.to raise_error(StandardError, 'boom')

            expect(store).to have_received(:append)
              .with(having_attributes(operation: 'action_failed', record_id: '4')).once
          end

          it 'records nothing when no audit database is configured' do
            allow(ForestAdminAgent::Facades::Container).to receive(:config_from_cache).and_return({})

            expect(execute).to eq({ type: 'Success', message: 'done' })
            expect(store).not_to have_received(:append)
          end

          # An action reporting failure through result_builder.error never raises, so only the result says so.
          it 'records an Error result as a failed run, and still returns it' do
            result = execute(result: { type: 'Error', message: 'not allowed' })

            expect(result).to eq({ type: 'Error', message: 'not allowed' })
            expect(store).to have_received(:append)
              .with(having_attributes(operation: 'action_failed', record_id: '4')).once
          end

          it 'records any other result type as a run that went through' do
            execute(result: { type: 'Webhook', url: 'https://example.test' })

            expect(store).to have_received(:append)
              .with(having_attributes(operation: 'action', record_id: '4')).once
          end
        end

        context 'with a global action' do
          let(:action_scope) { ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope::GLOBAL }

          it 'returns no id, since a global action targets no record' do
            expect(audited_ids({ ids: %w[4 7] })).to eq([])
          end
        end
      end
    end
  end
end
