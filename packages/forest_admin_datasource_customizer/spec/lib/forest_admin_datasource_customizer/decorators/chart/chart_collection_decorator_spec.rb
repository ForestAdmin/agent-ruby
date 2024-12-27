require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Chart
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminDatasourceToolkit::Decorators
      include ForestAdminDatasourceToolkit::Schema

      describe ChartCollectionDecorator do
        include_context 'with caller'

        before do
          @book = build_collection(
            {
              name: 'book',
              schema: {
                charts: ['child_chart'],
                fields: { id: build_numeric_primary_key }
              },
              list: [{ id: 123 }],
              render_chart: { countCurrent: 1 }
            }
          )

          @datasource = build_datasource_with_collections([@book])
          @decorated_datasource = DatasourceDecorator.new(@datasource, described_class)
          @decorated_book = @decorated_datasource.get_collection('book')
        end

        describe 'schema' do
          it 'not to be changed' do
            expect(@decorated_book.schema).to eq(@book.schema)
          end
        end

        describe 'add_chart' do
          it 'not let adding a chart with the same name' do
            expect do
              @decorated_book.add_chart('child_chart') { { countCurrent: 2 } }
            end.to raise_error(
              Exceptions::ForestException,
              '🌳🌳🌳 Chart child_chart already exists.'
            )
          end
        end

        context 'when a chart is added (single pk)' do
          before do
            @decorated_book.add_chart('new_chart') { { countCurrent: 2 } }
          end

          describe 'render_chart' do
            it 'call the child collection' do
              result = @decorated_book.render_chart(caller, 'child_chart', [123])

              expect(result).to eq({ countCurrent: 1 })
            end

            it 'call the chart block' do
              result = @decorated_book.render_chart(caller, 'new_chart', [123])

              expect(result).to eq({ countCurrent: 2 })
            end
          end
        end
      end
    end
  end
end
