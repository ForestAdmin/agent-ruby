require 'spec_helper'
require 'singleton'
require 'ostruct'

require 'json'

module ForestAdminAgent
  module Routes
    module Charts
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Schema
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes

      describe ApiChartCollection do
        include_context 'with caller'
        let(:args) do
          {
            headers: { 'HTTP_AUTHORIZATION' => bearer },
            params: {
              'collection_name' => 'book',
              'timezone' => 'Europe/Paris',
              'record_id' => 1
            }
          }
        end
        let(:permissions) { instance_double(ForestAdminAgent::Services::Permissions) }

        describe 'nominal case' do
          before do
            collection = build_collection(
              name: 'book',
              schema: { charts: ['my_chart'], fields: { 'id' => build_numeric_primary_key } },
              render_chart: { countCurrent: 12 }
            )
            @datasource = build_datasource_with_collections([collection])
            ForestAdminAgent::Facades::Container.instance.register(:datasource, @datasource)
          end

          it 'adds the routes' do
            chart = described_class.new(@datasource.get_collection('book'), 'my_chart')
            chart.setup_routes
            expect(chart.routes.include?('forest_chart_book_get_my_chart')).to be true
            expect(chart.routes.include?('forest_chart_book_post_my_chart')).to be true
            expect(chart.routes.length).to eq 2
          end

          describe 'with the route mounted' do
            it 'return the chart in a JSON-API response when call handle_api_chart' do
              chart = described_class.new(@datasource.get_collection('book'), 'my_chart')
              result = chart.handle_api_chart(args)
              {
                data: {
                  id: SecureRandom.uuid,
                  type: 'stats',
                  attributes: {
                    value: chart
                  }
                }
              }
              expect(result).to have_key(:content)
              expect(result[:content]).to have_key(:data)
              expect(result[:content][:data]).to have_key(:attributes)
              expect(result[:content][:data][:attributes]).to have_key(:value)
              expect(result[:content][:data][:attributes][:value]).to eq({ countCurrent: 12 })
            end

            it 'return the chart in a simple response when call handle_smart_chart' do
              chart = described_class.new(@datasource.get_collection('book'), 'my_chart')
              result = chart.handle_smart_chart(args)
              {
                data: {
                  id: SecureRandom.uuid,
                  type: 'stats',
                  attributes: {
                    value: chart
                  }
                }
              }
              expect(result).to have_key(:content)
              expect(result[:content]).to eq({ countCurrent: 12 })
            end
          end
        end
      end
    end
  end
end
