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

      describe Charts do
        include_context 'with caller'
        subject(:chart) { described_class.new }
        let(:args) do
          {
            headers: { 'HTTP_AUTHORIZATION' => bearer },
            params: {
              'collection_name' => 'book',
              'timezone' => 'Europe/Paris'
            }
          }
        end
        let(:permissions) { instance_double(ForestAdminAgent::Services::Permissions) }

        before do
          book_class = Struct.new(:id, :title, :price, :date, :year)
          stub_const('Book', book_class)
          book_review_class = Struct.new(:id, :book_id, :review_id)
          stub_const('BookReview', book_review_class)
          review_class = Struct.new(:id, :book_id, :author)
          stub_const('Review', review_class)

          datasource = Datasource.new
          collection_book = build_collection(
            name: 'book',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'title' => ColumnSchema.new(column_type: 'String', filter_operators: [Operators::EQUAL]),
                'price' => ColumnSchema.new(column_type: 'Number'),
                'date' => ColumnSchema.new(column_type: 'Date', filter_operators: [Operators::YESTERDAY]),
                'year' => ColumnSchema.new(column_type: 'Number', filter_operators: [Operators::EQUAL]),
                'reviews' => Relations::ManyToManySchema.new(
                  foreign_key: 'review_id',
                  foreign_key_target: 'id',
                  foreign_collection: 'review',
                  through_collection: 'book_review',
                  origin_key_target: 'id',
                  origin_key: 'book_id'
                ),
                'bookReviews' => Relations::OneToManySchema.new(
                  origin_key: 'book_id',
                  foreign_collection: 'review',
                  origin_key_target: 'id'
                )
              }
            }
          )
          collection_book_review = build_collection(
            name: 'book_review',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'book_id' => ColumnSchema.new(column_type: 'Number'),
                'review_id' => ColumnSchema.new(column_type: 'Number'),
                'book' => Relations::ManyToOneSchema.new(
                  foreign_key: 'book_id',
                  foreign_collection: 'book',
                  foreign_key_target: 'id'
                ),
                'review' => Relations::ManyToOneSchema.new(
                  foreign_key: 'review_id',
                  foreign_collection: 'review',
                  foreign_key_target: 'id'
                )
              }
            }
          )
          collection_review = build_collection(
            name: 'review',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'author' => ColumnSchema.new(column_type: 'String'),
                'book_id' => ColumnSchema.new(column_type: 'Number'),
                'book' => Relations::ManyToOneSchema.new(
                  foreign_key: 'book_id',
                  foreign_collection: 'book',
                  foreign_key_target: 'id'
                )
              }
            }
          )
          allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)
          datasource.add_collection(collection_book)
          datasource.add_collection(collection_review)
          datasource.add_collection(collection_book_review)
          ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(datasource)
          ForestAdminAgent::Builder::AgentFactory.instance.build

          @datasource = ForestAdminAgent::Facades::Container.datasource

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

        it 'adds the route forest_chart' do
          chart.setup_routes
          expect(chart.routes.include?('forest_chart')).to be true
          expect(chart.routes.length).to eq 1
        end

        it 'throw an error when request has a bad chart type' do
          args[:params][:type] = 'unknown_type'

          expect do
            chart.handle_request(args)
          end.to raise_error(
            ForestAdminDatasourceToolkit::Exceptions::ForestException, '🌳🌳🌳 Invalid Chart type unknown_type'
          )
        end

        describe 'makeValue' do
          it 'return a valueChart' do
            args[:params] = args[:params].merge({
                                                  aggregateFieldName: 'price',
                                                  aggregator: 'Sum',
                                                  sourceCollectionName: 'book',
                                                  type: 'Value',
                                                  timezone: 'Europe/Paris'
                                                })
            allow(@datasource.get_collection('book')).to receive(:aggregate).and_return([{ 'value' => 10, 'group' => [] }])
            result = chart.handle_request(args)

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

          it 'return a valueChart with previous filter' do
            args[:params] = args[:params].merge({
                                                  aggregateFieldName: 'price',
                                                  aggregator: 'Sum',
                                                  sourceCollectionName: 'book',
                                                  filter: '{"field":"date","operator":"yesterday","value":null}',
                                                  type: 'Value',
                                                  timezone: 'Europe/Paris'
                                                })
            @datasource.get_collection('book')
            allow(@datasource.get_collection('book')).to receive(:aggregate).and_return(
              [{ 'value' => 10, 'group' => [] }], # first call
              [{ 'value' => 5, 'group' => [] }] # second call
            )
            result = chart.handle_request(args)

            expect(result).to match(
              content: {
                data: {
                  id: be_a(String),
                  type: 'stats',
                  attributes: {
                    value: { countCurrent: 10, countPrevious: 5 }
                  }
                }
              }
            )
          end
        end

        describe 'makeObjective' do
          it 'return a ObjectiveChart' do
            args[:params] = args[:params].merge({
                                                  aggregateFieldName: 'price',
                                                  aggregator: 'Count',
                                                  sourceCollectionName: 'book',
                                                  type: 'Objective',
                                                  timezone: 'Europe/Paris'
                                                })
            allow(@datasource.get_collection('book')).to receive(:aggregate).and_return([{ 'value' => 10, 'group' => [] }])
            result = chart.handle_request(args)

            expect(result).to match(
              content: {
                data: {
                  id: be_a(String),
                  type: 'stats',
                  attributes: {
                    value: { value: 10 }
                  }
                }
              }
            )
          end
        end

        describe 'makePie' do
          it 'return a PieChart' do
            args[:params] = args[:params].merge({
                                                  groupByFieldName: 'year',
                                                  aggregator: 'Count',
                                                  sourceCollectionName: 'book',
                                                  type: 'Pie',
                                                  timezone: 'Europe/Paris'
                                                })
            allow(@datasource.get_collection('book')).to receive(:aggregate).and_return(
              [
                { 'value' => 100, 'group' => { 'year' => 2021 } },
                { 'value' => 150, 'group' => { 'year' => 2022 } }
              ]
            )
            result = chart.handle_request(args)

            expect(result).to match(
              content: {
                data: {
                  id: be_a(String),
                  type: 'stats',
                  attributes: {
                    value: [{ key: 2021, value: 100 }, { key: 2022, value: 150 }]
                  }
                }
              }
            )
          end
        end

        describe 'makeLine' do
          it 'return a LineChart with day time range' do
            args[:params] = args[:params].merge({
                                                  groupByFieldName: 'date',
                                                  aggregator: 'Count',
                                                  sourceCollectionName: 'book',
                                                  timeRange: 'Day',
                                                  type: 'Line',
                                                  timezone: 'Europe/Paris'
                                                })
            allow(@datasource.get_collection('book')).to receive(:aggregate).and_return(
              [
                { 'value' => 10, 'group' => { 'date' => Time.parse('2022-01-03 00:00:00') } },
                { 'value' => 15, 'group' => { 'date' => Time.parse('2022-01-07 00:00:00') } }
              ]
            )
            result = chart.handle_request(args)

            expect(result).to match(
              content: {
                data: {
                  id: be_a(String),
                  type: 'stats',
                  attributes: {
                    value: [
                      { label: '03/01/2022', values: { value: 10 } },
                      { label: '04/01/2022', values: { value: 0 } },
                      { label: '05/01/2022', values: { value: 0 } },
                      { label: '06/01/2022', values: { value: 0 } },
                      { label: '07/01/2022', values: { value: 15 } }
                    ]
                  }
                }
              }
            )
          end

          it 'return a LineChart with week time range' do
            args[:params] = args[:params].merge({
                                                  groupByFieldName: 'date',
                                                  aggregator: 'Count',
                                                  sourceCollectionName: 'book',
                                                  timeRange: 'Week',
                                                  type: 'Line',
                                                  timezone: 'Europe/Paris'
                                                })
            allow(@datasource.get_collection('book')).to receive(:aggregate).and_return(
              [
                { 'value' => 10, 'group' => { 'date' => Time.parse('2022-01-03 00:00:00') } },
                { 'value' => 15, 'group' => { 'date' => Time.parse('2022-01-10 00:00:00') } }
              ]
            )
            result = chart.handle_request(args)

            expect(result).to match(
              content: {
                data: {
                  id: be_a(String),
                  type: 'stats',
                  attributes: {
                    value: [
                      { label: 'W01-2022', values: { value: 10 } },
                      { label: 'W02-2022', values: { value: 15 } }
                    ]
                  }
                }
              }
            )
          end

          it 'return a LineChart with week time range - should be iso date' do
            args[:params] = args[:params].merge({
                                                  groupByFieldName: 'date',
                                                  aggregator: 'Count',
                                                  sourceCollectionName: 'book',
                                                  timeRange: 'Week',
                                                  type: 'Line',
                                                  timezone: 'Europe/Paris'
                                                })
            allow(@datasource.get_collection('book')).to receive(:aggregate).and_return(
              [
                { 'value' => 10, 'group' => { 'date' => Time.parse('2024-12-23 00:00:00') } },
                { 'value' => 15, 'group' => { 'date' => Time.parse('2024-12-30 00:00:00') } },
                { 'value' => 20, 'group' => { 'date' => Time.parse('2025-01-06 00:00:00') } }
              ]
            )
            result = chart.handle_request(args)

            expect(result).to match(
              content: {
                data: {
                  id: be_a(String),
                  type: 'stats',
                  attributes: {
                    value: [
                      { label: 'W52-2024', values: { value: 10 } },
                      { label: 'W01-2025', values: { value: 15 } },
                      { label: 'W02-2025', values: { value: 20 } }
                    ]
                  }
                }
              }
            )
          end

          it 'return a LineChart with month time range' do
            args[:params] = args[:params].merge({
                                                  groupByFieldName: 'date',
                                                  aggregator: 'Count',
                                                  sourceCollectionName: 'book',
                                                  timeRange: 'Month',
                                                  type: 'Line',
                                                  timezone: 'Europe/Paris'
                                                })
            allow(@datasource.get_collection('book')).to receive(:aggregate).and_return(
              [
                { 'value' => 10, 'group' => { 'date' => Time.parse('2022-01-01 00:00:00') } },
                { 'value' => 15, 'group' => { 'date' => Time.parse('2022-02-01 00:00:00') } }
              ]
            )
            result = chart.handle_request(args)

            expect(result).to match(
              content: {
                data: {
                  id: be_a(String),
                  type: 'stats',
                  attributes: {
                    value: [
                      { label: 'Jan 22', values: { value: 10 } },
                      { label: 'Feb 22', values: { value: 15 } }
                    ]
                  }
                }
              }
            )
          end

          it 'return a LineChart with year time range' do
            args[:params] = args[:params].merge({
                                                  groupByFieldName: 'date',
                                                  aggregator: 'Count',
                                                  sourceCollectionName: 'book',
                                                  timeRange: 'Year',
                                                  type: 'Line',
                                                  timezone: 'Europe/Paris'
                                                })
            allow(@datasource.get_collection('book')).to receive(:aggregate).and_return(
              [
                { 'value' => 10, 'group' => { 'date' => Time.parse('2022-01-01 00:00:00') } },
                { 'value' => 15, 'group' => { 'date' => Time.parse('2023-01-01 00:00:00') } }
              ]
            )
            result = chart.handle_request(args)

            expect(result).to match(
              content: {
                data: {
                  id: be_a(String),
                  type: 'stats',
                  attributes: {
                    value: [
                      { label: '2022', values: { value: 10 } },
                      { label: '2023', values: { value: 15 } }
                    ]
                  }
                }
              }
            )
          end
        end

        describe 'makeLeaderboard' do
          it 'return a LeaderboardChart with a OneToMany Relation' do
            args[:params] = args[:params].merge({
                                                  labelFieldName: 'author',
                                                  relationshipFieldName: 'bookReviews',
                                                  aggregator: 'Count',
                                                  aggregateFieldName: 'id',
                                                  sourceCollectionName: 'book',
                                                  type: 'Leaderboard',
                                                  timezone: 'Europe/Paris'
                                                })
            allow(@datasource.get_collection('book')).to receive(:datasource).and_return(@datasource)
            allow(@datasource.get_collection('review')).to receive(:aggregate).and_return(
              [
                { 'value' => 10, 'group' => { 'author' => 'Isaac Asimov' } },
                { 'value' => 15, 'group' => { 'author' => 'Jules Verne' } }
              ]
            )
            result = chart.handle_request(args)

            expect(result).to match(
              content: {
                data: {
                  id: be_a(String),
                  type: 'stats',
                  attributes: {
                    value: [{ key: nil, value: 10 }, { key: nil, value: 15 }]
                  }
                }
              }
            )
          end

          it 'return a LeaderboardChart with a ManyToMany Relation' do
            args[:params] = args[:params].merge({
                                                  labelFieldName: 'year',
                                                  relationshipFieldName: 'reviews',
                                                  aggregator: 'Count',
                                                  aggregateFieldName: 'id',
                                                  sourceCollectionName: 'book',
                                                  type: 'Leaderboard',
                                                  timezone: 'Europe/Paris'
                                                })
            allow(@datasource.get_collection('book')).to receive(:datasource).and_return(@datasource)
            allow(@datasource.get_collection('book_review')).to receive(:aggregate).and_return(
              [
                { 'value' => 10, 'group' => { 'book:year' => 2022 } },
                { 'value' => 15, 'group' => { 'book:year' => 2023 } }
              ]
            )
            result = chart.handle_request(args)

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

          it 'throw a ForestException when the request is not filled correctly' do
            args[:params] = args[:params].merge({
                                                  relationshipFieldName: 'unknown_relation',
                                                  aggregator: 'Count',
                                                  sourceCollectionName: 'book',
                                                  type: 'Leaderboard',
                                                  timezone: 'Europe/Paris'
                                                })

            expect do
              chart.handle_request(args)
            end.to raise_error(
              ForestAdminDatasourceToolkit::Exceptions::ForestException,
              '🌳🌳🌳 Failed to generate leaderboard chart: parameters do not match pre-requisites'
            )
          end
        end

        describe 'inject_context_variables' do
          it 'overrides the filter with the context variables' do
            args[:params] = args[:params].merge(
              {
                type: 'Value',
                sourceCollectionName: 'book',
                aggregateFieldName: nil,
                aggregator: 'Count',
                filter: JSON.generate({
                                        aggregator: 'and',
                                        conditions: [
                                          { operator: 'equal', value: '{{dropdown1.selectedValue}}', field: 'title' }
                                        ]
                                      }),
                contextVariables: { 'dropdown1.selectedValue' => 'FOO' },
                timezone: 'Europe/Paris'
              }
            )
            allow(@datasource.get_collection('book')).to receive(:aggregate).and_return([{ 'value' => 10, 'group' => [] }])
            chart.handle_request(args)

            expect(chart.filter).to have_attributes(
              condition_tree: have_attributes(field: 'title', operator: Operators::EQUAL, value: 'FOO'),
              search: nil,
              search_extended: nil,
              segment: nil,
              sort: nil,
              page: nil
            )
          end

          it 'does not override the filter when there is no filter with a context variable' do
            args[:params] = args[:params].merge({
                                                  type: 'Value',
                                                  sourceCollectionName: 'book',
                                                  aggregateFieldName: nil,
                                                  aggregator: 'Count',
                                                  timezone: 'Europe/Paris'
                                                })
            allow(@datasource.get_collection('book')).to receive(:aggregate).and_return([{ 'value' => 10, 'group' => [] }])
            chart.handle_request(args)

            expect(chart.filter).to have_attributes(
              condition_tree: nil,
              search: nil,
              search_extended: nil,
              segment: nil,
              sort: nil,
              page: nil
            )
          end
        end
      end
    end
  end
end
