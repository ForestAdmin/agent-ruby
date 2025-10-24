require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Chart
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminDatasourceToolkit::Decorators
      include ForestAdminDatasourceToolkit::Schema

      describe ChartDatasourceDecorator do
        include_context 'with caller'

        context 'when decorating an empty datasource' do
          let(:datasource) { build_datasource }
          let(:decorator) { described_class.new(datasource) }

          context 'with no charts' do
            it 'schema should be empty' do
              expect(decorator.schema).to eq({ charts: [] })
            end

            it 'proxy call when calling render_chart' do
              decorator.render_chart(caller, 'my_chart')

              expect(datasource).to have_received(:render_chart)
            end
          end

          context 'with a chart' do
            before do
              decorator.add_chart('my_chart') do |_ctx, result_builder|
                result_builder.value(34, 45)
              end
            end

            it 'raise an error if a chart already exists' do
              expect do
                decorator.add_chart('my_chart')
              end.to raise_error(ForestAdminAgent::Http::Exceptions::ConflictError, 'Chart my_chart already exists.')
            end

            it 'schema should not be empty' do
              expect(decorator.schema).to eq({ charts: ['my_chart'] })
            end

            it 'not proxy call when calling render_chart' do
              result = decorator.render_chart(caller, 'my_chart')

              expect(result).to eq({ countCurrent: 34, countPrevious: 45 })
              expect(datasource).not_to have_received(:render_chart)
            end
          end
        end

        context 'when decorating a datasource with charts' do
          let(:datasource) { build_datasource({ schema: { charts: ['my_chart'] } }) }
          let(:decorator) { described_class.new(datasource) }

          it 'raise an error when adding a duplicate' do
            expect do
              decorator.add_chart('my_chart')
            end.to raise_error(ForestAdminAgent::Http::Exceptions::ConflictError, 'Chart my_chart already exists.')
          end
        end

        context 'when adding charts on a lower layer' do
          let(:datasource) { build_datasource }
          let(:first_decorator) { described_class.new(datasource) }
          let(:second_decorator) { described_class.new(first_decorator) }

          it 'raise an error when adding a duplicate and call schema' do
            second_decorator.add_chart('my_chart')
            first_decorator.add_chart('my_chart')

            expect(datasource.schema).to eq({ charts: [] })
            expect(first_decorator.schema).to eq({ charts: ['my_chart'] })
            expect do
              second_decorator.schema
            end.to raise_error(ForestAdminAgent::Http::Exceptions::ConflictError, 'Chart my_chart is defined twice.')
          end
        end
      end
    end
  end
end
