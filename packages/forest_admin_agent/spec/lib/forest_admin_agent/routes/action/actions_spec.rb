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
