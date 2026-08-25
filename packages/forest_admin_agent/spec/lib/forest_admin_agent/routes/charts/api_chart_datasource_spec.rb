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

      describe ApiChartDatasource do
        include_context 'with caller'
        let(:args) do
          {
            headers: { 'HTTP_AUTHORIZATION' => bearer },
            params: {
              'timezone' => 'Europe/Paris',
              'record_id' => 1
            }
          }
        end
        let(:permissions) { instance_double(ForestAdminAgent::Services::Permissions) }

        describe 'nominal case' do
          before do
            datasource = build_datasource(
              schema: { charts: ['my_chart'] },
              render_chart: { countCurrent: 12 }
            )
            ForestAdminAgent::Facades::Container.instance.register(:datasource, datasource)
            allow(ForestAdminAgent::Services::Permissions).to receive(:new).and_return(permissions)
          end

          it 'adds the routes' do
            chart = described_class.new('my_chart')
            chart.setup_routes
            expect(chart.routes.include?('forest_chart_get_my_chart')).to be true
            expect(chart.routes.include?('forest_chart_post_my_chart')).to be true
            expect(chart.routes.length).to eq 2
          end

          describe 'with the route mounted' do
            it 'return the chart in a JSON-API response when call handle_api_chart' do
              chart = described_class.new('my_chart')
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
              chart = described_class.new('my_chart')
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

          describe 'when the request is not authenticated' do
            let(:args) do
              {
                headers: {},
                params: { 'timezone' => 'Europe/Paris' }
              }
            end

            it 'rejects handle_api_chart with no Authorization header' do
              expect { described_class.new('my_chart').handle_api_chart(args) }.to raise_error(
                ForestAdminAgent::Http::Exceptions::UnauthorizedError
              )
            end

            it 'rejects handle_smart_chart with no Authorization header' do
              expect { described_class.new('my_chart').handle_smart_chart(args) }.to raise_error(
                ForestAdminAgent::Http::Exceptions::UnauthorizedError
              )
            end
          end

          describe 'when the request carries a remote ip' do
            let(:args) do
              {
                headers: { 'HTTP_AUTHORIZATION' => bearer, 'action_dispatch.remote_ip' => '10.0.0.1' },
                params: { 'timezone' => 'Europe/Paris' }
              }
            end

            before do
              allow(ForestAdminAgent::Facades::Whitelist).to receive(:check_ip)
            end

            it 'checks the ip against the whitelist on handle_api_chart' do
              described_class.new('my_chart').handle_api_chart(args)
              expect(ForestAdminAgent::Facades::Whitelist).to have_received(:check_ip).with('10.0.0.1')
            end

            it 'checks the ip against the whitelist on handle_smart_chart' do
              described_class.new('my_chart').handle_smart_chart(args)
              expect(ForestAdminAgent::Facades::Whitelist).to have_received(:check_ip).with('10.0.0.1')
            end
          end
        end
      end
    end
  end
end
