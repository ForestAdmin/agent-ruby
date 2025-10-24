require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Segment
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminDatasourceToolkit::Decorators
      include ForestAdminDatasourceToolkit::Schema

      describe SegmentCollectionDecorator do
        before do
          datasource = Datasource.new
          @collection = build_collection(
            name: 'book',
            schema: {
              fields: {
                'name' => build_column({ filter_operators: [Operators::EQUAL, Operators::IN] })
              }
            }
          )
          datasource.add_collection(@collection)

          @decorated_datasource = DatasourceDecorator.new(datasource, described_class)
          @decorated_collection = @decorated_datasource.get_collection('book')
        end

        context 'when there is no filter' do
          describe 'refine_filter' do
            it 'return nil' do
              condition_tree_generator = instance_double(Proc, call: nil)
              @decorated_collection.add_segment('segment_name', condition_tree_generator)

              filter = @decorated_collection.refine_filter(caller)

              expect(filter).to be_nil
              expect(condition_tree_generator).not_to have_received(:call)
            end
          end
        end

        context 'when there is a filter' do
          context 'when the segment is not managed by this decorator' do
            describe 'refine_filter' do
              it 'return the given filter' do
                condition_tree_generator = instance_double(Proc, call: nil)
                @decorated_collection.add_segment('segment_name', condition_tree_generator)

                a_filter = Filter.new(segment: 'a_segment')
                filter = @decorated_collection.refine_filter(caller, a_filter)

                expect(filter.to_h).to eq(a_filter.to_h)
                expect(condition_tree_generator).not_to have_received(:call)
              end
            end
          end

          context 'when the segment is managed by this decorator' do
            describe 'refine_filter' do
              it 'return the filter with the merged conditionTree' do
                condition_tree_generator = Nodes::ConditionTreeLeaf.new('name', Operators::EQUAL, 'foo')
                @decorated_collection.add_segment('segment_name', condition_tree_generator)
                a_filter = Filter.new(
                  segment: 'segment_name',
                  condition_tree: Nodes::ConditionTreeLeaf.new('name', Operators::EQUAL, 'other_value')
                )
                filter = @decorated_collection.refine_filter(caller, a_filter)

                expect(filter.segment).to be_nil
                expect(filter.condition_tree.to_h).to eq(
                  {
                    aggregator: 'And',
                    conditions: [
                      { field: 'name', operator: Operators::EQUAL, value: 'foo' },
                      { field: 'name', operator: Operators::EQUAL, value: 'other_value' }
                    ]
                  }
                )
              end

              it 'raise an error when a conditionTree is not valid' do
                condition_tree_generator = instance_double(
                  Proc,
                  call: Nodes::ConditionTreeLeaf.new('do not exists', Operators::EQUAL, 'foo')
                )
                @decorated_collection.add_segment('segment_name', condition_tree_generator)

                expect do
                  @decorated_collection.refine_filter(caller, Filter.new(segment: 'segment_name'))
                end.to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException, 'Column not found book.do not exists')
              end
            end
          end
        end
      end
    end
  end
end
