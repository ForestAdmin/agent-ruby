require 'spec_helper'
require 'shared/caller'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Chart
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Decorators
      include ForestAdminDatasourceToolkit::Schema
      include ForestAdminDatasourceToolkit::Components::Query
      describe ChartContext do
        include_context 'with caller'
        before do
          collection = build_collection(
            name: 'my_collection',
            schema: {
              fields: { 'id1' => build_numeric_primary_key, 'id2' => build_numeric_primary_key }
            },
            list: [{ id1: 1, id2: 2 }]
          )

          @context = described_class.new(collection, caller, [1, 2])
        end

        describe 'record_id' do
          it 'raise an error' do
            expect { @context.record_id }.to raise_error(
              ForestAdminDatasourceToolkit::Exceptions::ForestException,
              "🌳🌳🌳 Collection is using a composite pk: use 'context.composite_record_id'."
            )
          end
        end

        describe 'composite_record_id' do
          it 'return the record id' do
            expect(@context.composite_record_id).to eq([1, 2])
          end
        end

        describe 'get_record' do
          it 'return the record' do
            record = @context.get_record(%w[id1 id2])

            expect(record).to eq({ id1: 1, id2: 2 })
          end
        end
      end
    end
  end
end
