require 'spec_helper'
require 'singleton'
require 'ostruct'
require 'shared/caller'
require 'json'

module ForestAdminAgent
  module Routes
    module Resources
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Exceptions
      include ForestAdminDatasourceToolkit::Schema

      describe NativeQuery do
        include_context 'with caller'
        subject(:native_query) { described_class.new }
        let(:args) do
          {
            headers: { 'HTTP_AUTHORIZATION' => bearer },
            params: {
              'connectionName' => 'primary',
              'timezone' => 'Europe/Paris'
            }
          }
        end
        let(:permissions) { instance_double(ForestAdminAgent::Services::Permissions) }

        before do
          @root_datasource = Datasource.new
          ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(@root_datasource)
          ForestAdminAgent::Builder::AgentFactory.instance.build
          customizer = instance_double(
            ForestAdminDatasourceCustomizer::DatasourceCustomizer,
            get_root_datasource_by_connection: @root_datasource
          )
          allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive_messages(
            send_schema: nil,
            customizer: customizer
          )

          allow(ForestAdminAgent::Services::Permissions).to receive(:new).and_return(permissions)
          allow(permissions).to receive_messages(
            can_chart?: true,
            get_scope: nil,
            get_user_data: {
              id: 1,
              firstName: 'John',
              lastName: 'Doe',
              fullName: 'John Doe',
              email: 'johndoe@forestadmin.com',
              tags: { 'foo' => 'bar' },
              roleId: 1,
              permissionLevel: 'admin'
            },
            get_team: { id: 100, name: 'Operations' }
          )
        end

        it 'adds the route forest_native_query' do
          native_query.setup_routes
          expect(native_query.routes.include?('forest_native_query')).to be true
          expect(native_query.routes.length).to eq 1
        end

        it 'throw an error when request has a bad chart type' do
          args[:params][:type] = 'unknown_type'
          args[:params][:query] = 'select * from table'

          expect do
            native_query.handle_request(args)
          end.to raise_error(
            ForestException, '🌳🌳🌳 Invalid Chart type unknown_type'
          )
        end

        describe 'makeValue' do
          it 'return a valueChart' do
            args[:params] = args[:params].merge(
              {
                query: 'SELECT COUNT(*) AS value FROM customers;',
                type: 'Value',
                connectionName: 'primary'
              }
            )
            allow(@root_datasource).to receive(:execute_native_query).and_return([{ value: 10 }])
            result = native_query.handle_request(args)

            expect(result).to match(
              content: {
                data: {
                  id: be_a(String),
                  type: 'stats',
                  attributes: {
                    value: { countCurrent: 10, countPrevious: nil }
                  }
                }
              }
            )
          end

          it 'return a valueChart with previous value' do
            args[:params] = args[:params].merge(
              {
                query: 'SELECT COUNT(*) AS value, COUNT(*) AS previous FROM customers;',
                type: 'Value',
                connectionName: 'primary'
              }
            )
            allow(@root_datasource).to receive(:execute_native_query).and_return([{ value: 10, previous: 10 }])
            result = native_query.handle_request(args)

            expect(result).to match(
              content: {
                data: {
                  id: be_a(String),
                  type: 'stats',
                  attributes: {
                    value: { countCurrent: 10, countPrevious: 10 }
                  }
                }
              }
            )
          end

          it 'raise an error if result query has not the expected column' do
            args[:params] = args[:params].merge(
              {
                query: 'SELECT COUNT(*) AS foo FROM customers;',
                type: 'Value',
                connectionName: 'primary'
              }
            )
            allow(@root_datasource).to receive(:execute_native_query).and_return([{ foo: 10 }])

            expect { native_query.handle_request(args) }.to raise_error(
              ForestException,
              "🌳🌳🌳 The result columns must be named 'value' instead of 'foo'"
            )
          end
        end

        describe 'makeObjective' do
          it 'return a objectiveChart' do
            args[:params] = args[:params].merge(
              {
                query: 'SELECT COUNT(orders) AS value, 750 AS objective FROM orders;',
                type: 'Objective',
                connectionName: 'primary'
              }
            )
            allow(@root_datasource).to receive(:execute_native_query).and_return(
              [{ value: 200, objective: 750 }]
            )
            result = native_query.handle_request(args)

            expect(result).to match(
              content: {
                data: {
                  id: be_a(String),
                  type: 'stats',
                  attributes: {
                    value: { value: 200, objective: 750 }
                  }
                }
              }
            )
          end

          it 'SELECT COUNT(orders) AS foo, 750 AS objective FROM orders;' do
            args[:params] = args[:params].merge(
              {
                query: 'SELECT COUNT(*) AS foo FROM customers;',
                type: 'Value',
                connectionName: 'primary'
              }
            )
            allow(@root_datasource).to receive(:execute_native_query).and_return([{ foo: 10 }])

            expect { native_query.handle_request(args) }.to raise_error(
              ForestException,
              "🌳🌳🌳 The result columns must be named 'value' instead of 'foo'"
            )
          end
        end

        describe 'makePie' do
          it 'return a PieChart' do
            args[:params] = args[:params].merge(
              {
                query: 'SELECT transactions.status AS key, COUNT(*) AS value FROM transactions GROUP BY status;',
                type: 'Pie',
                connectionName: 'primary'
              }
            )
            allow(@root_datasource).to receive(:execute_native_query).and_return(
              [{ key: 'pending', value: 10 }, { key: 'done', value: 100 }]
            )
            result = native_query.handle_request(args)

            expect(result).to match(
              content: {
                data: {
                  id: be_a(String),
                  type: 'stats',
                  attributes: {
                    value: [{ key: 'pending', value: 10 }, { key: 'done', value: 100 }]
                  }
                }
              }
            )
          end

          it 'raise an error if result query has not the expected column' do
            args[:params] = args[:params].merge(
              {
                query: 'SELECT transactions.status AS foo, COUNT(*) AS value FROM transactions GROUP BY status;',
                type: 'Pie',
                connectionName: 'primary'
              }
            )
            allow(@root_datasource).to receive(:execute_native_query).and_return([{ foo: 10 }])

            expect { native_query.handle_request(args) }.to raise_error(
              ForestException,
              "🌳🌳🌳 The result columns must be named 'key', 'value' instead of 'foo'"
            )
          end
        end

        describe 'makeLine' do
          it 'return a LineChart with day time range' do
            args[:params] = args[:params].merge(
              {
                query: "SELECT DATE_TRUNC('month', start_date) AS key, COUNT(*) as value
                        FROM appointments GROUP BY key ORDER BY key;",
                type: 'Line',
                connectionName: 'primary'
              }
            )
            allow(@root_datasource).to receive(:execute_native_query).and_return(
              [
                { value: 10, key: '2022-01-01 00:00:00' },
                { value: 15, key: '2022-02-01 00:00:00' }
              ]
            )
            result = native_query.handle_request(args)

            expect(result).to match(
              content: {
                data: {
                  id: be_a(String),
                  type: 'stats',
                  attributes: {
                    value: [
                      { label: '2022-01-01 00:00:00', values: { value: 10 } },
                      { label: '2022-02-01 00:00:00', values: { value: 15 } }
                    ]
                  }
                }
              }
            )
          end

          it 'raise an error if result query has not the expected column' do
            args[:params] = args[:params].merge(
              {
                query: "SELECT DATE_TRUNC('month', start_date) AS foo, COUNT(*) as value
                        FROM appointments GROUP BY key ORDER BY key;",
                type: 'Line',
                connectionName: 'primary'
              }
            )
            allow(@root_datasource).to receive(:execute_native_query).and_return(
              [
                { value: 10, foo: '2022-01-01 00:00:00' },
                { value: 15, foo: '2022-02-01 00:00:00' }
              ]
            )

            expect { native_query.handle_request(args) }.to raise_error(
              ForestException,
              "🌳🌳🌳 The result columns must be named 'key', 'value' instead of 'value', 'foo'"
            )
          end
        end

        describe 'makeLeaderboard' do
          it 'return a LeaderboardChart' do
            args[:params] = args[:params].merge(
              {
                query: "SELECT companies.name AS key, SUM(transactions.amount) AS value
                        FROM transactions
                        JOIN companies ON transactions.beneficiary_company_id = companies.id
                        GROUP BY key
                        ORDER BY value DESC
                        LIMIT 10;",
                type: 'Leaderboard',
                connectionName: 'primary'
              }
            )
            allow(@root_datasource).to receive(:execute_native_query).and_return(
              [
                { value: 10, key: 2022  },
                { value: 15, key: 2023  }
              ]
            )

            result = native_query.handle_request(args)

            expect(result).to match(
              content: {
                data: {
                  id: be_a(String),
                  type: 'stats',
                  attributes: {
                    value: [{ key: 2022, value: 10 }, { key: 2023, value: 15 }]
                  }
                }
              }
            )
          end

          it 'raise an error if result query has not the expected column' do
            args[:params] = args[:params].merge(
              {
                query: "SELECT companies.name AS foo, SUM(transactions.amount) AS value
                        FROM transactions
                        JOIN companies ON transactions.beneficiary_company_id = companies.id
                        GROUP BY key
                        ORDER BY value DESC
                        LIMIT 10;",
                type: 'Leaderboard',
                connectionName: 'primary'
              }
            )
            allow(@root_datasource).to receive(:execute_native_query).and_return(
              [
                { value: 10, foo: 2022  },
                { value: 15, foo: 2023  }
              ]
            )

            expect { native_query.handle_request(args) }.to raise_error(
              ForestException,
              "🌳🌳🌳 The result columns must be named 'key', 'value' instead of 'value', 'foo'"
            )
          end
        end

        describe 'inject_context_variables' do
          it 'overrides the query with the context variables' do
            args[:params] = args[:params].merge(
              {
                query: 'SELECT COUNT(*) AS value FROM customers WHERE id > {{dropdown1.selectedValue}};',
                type: 'Value',
                connectionName: 'primary',
                contextVariables: { 'dropdown1.selectedValue' => 'FOO' },
                timezone: 'Europe/Paris'
              }
            )

            allow(@root_datasource).to receive(:execute_native_query).and_return([{ value: 10, previous: 10 }])
            native_query.handle_request(args)

            expect(@root_datasource).to have_received(:execute_native_query) do |connection_name, query, binds|
              expect(connection_name).to eq('primary')
              expect(query).to eq('SELECT COUNT(*) AS value FROM customers WHERE id > $1;')
              expect(binds).to eq(['FOO'])
            end
          end
        end
      end
    end
  end
end
