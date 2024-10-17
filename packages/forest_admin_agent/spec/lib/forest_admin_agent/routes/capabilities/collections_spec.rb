require 'spec_helper'
require 'shared/caller'

module ForestAdminAgent
  module Routes
    module Capabilities
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminDatasourceToolkit::Schema
      describe Collections do
        include_context 'with caller'
        subject(:capabilities_collections) { described_class.new }
        let(:permissions) { instance_double(ForestAdminAgent::Services::Permissions) }

        before do
          datasource = Datasource.new
          collection_user = collection_build(
            name: 'user',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true, filter_operators: [Operators::IN, Operators::EQUAL, Operators::GREATER_THAN, Operators::LESS_THAN]),
                'first_name' => ColumnSchema.new(column_type: 'String', filter_operators: [Operators::PRESENT, Operators::EQUAL]),
                'last_name' => ColumnSchema.new(column_type: 'String', filter_operators: [Operators::PRESENT, Operators::EQUAL])
              }
            }
          )

          collection_book = collection_build(
            name: 'book',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true, filter_operators: [Operators::EQUAL]),
                'title' => ColumnSchema.new(column_type: 'String', filter_operators: [Operators::PRESENT, Operators::EQUAL]),
                'price' => ColumnSchema.new(column_type: 'Number', filter_operators: [Operators::GREATER_THAN, Operators::LESS_THAN]),
                'date' => ColumnSchema.new(column_type: 'Date', filter_operators: [Operators::YESTERDAY]),
                'year' => ColumnSchema.new(column_type: 'Number', filter_operators: [Operators::EQUAL])
              }
            }
          )

          datasource.add_collection(collection_user)
          allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)
          datasource.add_collection(collection_book)
          ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(datasource)
          ForestAdminAgent::Builder::AgentFactory.instance.build
          @datasource = ForestAdminAgent::Facades::Container.datasource
          allow(ForestAdminAgent::Services::Permissions).to receive(:new).and_return(permissions)
        end

        it 'adds the route forest_list' do
          capabilities_collections.setup_routes
          expect(capabilities_collections.routes.include?('forest_capabilities_collections')).to be true
          expect(capabilities_collections.routes.length).to eq 1
        end

        context 'when there is no collectionNames in params' do
          it 'return all collections' do
            args = {
              headers: { 'HTTP_AUTHORIZATION' => bearer },
              params: {
                'timezone' => 'Europe/Paris'
              }
            }
            result = capabilities_collections.handle_request(args)

            expect(result[:content][:collections].length).to eq(2)
            expect(result[:content][:collections][0]).to eq({
                                                              name: 'user',
                                                              fields: [
                                                                { name: 'id', type: 'Number', operators: %w[Equal GreaterThan LessThan Blank In Missing] },
                                                                { name: 'first_name', type: 'String', operators: %w[Equal Present Blank In Missing] },
                                                                { name: 'last_name', type: 'String', operators: %w[Equal Present Blank In Missing] }
                                                              ]
                                                            })
            expect(result[:content][:collections][1]).to eq({
                                                              name: 'book',
                                                              fields: [
                                                                { name: 'id', type: 'Number', operators: %w[Equal Blank In Missing] },
                                                                { name: 'title', type: 'String', operators: %w[Equal Present Blank In Missing] },
                                                                { name: 'price', type: 'Number', operators: %w[GreaterThan LessThan] },
                                                                { name: 'date', type: 'Date', operators: %w[Yesterday] },
                                                                { name: 'year', type: 'Number', operators: %w[Equal Blank In Missing] }
                                                              ]
                                                            })
          end
        end

        context 'when there is collectionNames in params' do
          it 'return the collections provided in params' do
            args = {
              headers: { 'HTTP_AUTHORIZATION' => bearer },
              params: {
                'collectionNames' => ['user'],
                'timezone' => 'Europe/Paris'
              }
            }
            result = capabilities_collections.handle_request(args)

            expect(result[:content][:collections].length).to eq(1)
            expect(result[:content][:collections][0]).to eq({
                                                              name: 'user',
                                                              fields: [
                                                                { name: 'id', type: 'Number', operators: %w[Equal GreaterThan LessThan Blank In Missing] },
                                                                { name: 'first_name', type: 'String', operators: %w[Equal Present Blank In Missing] },
                                                                { name: 'last_name', type: 'String', operators: %w[Equal Present Blank In Missing] }
                                                              ]
                                                            })
          end
        end

        it 'throws an error when th collection does not exist' do
          args = {
            headers: { 'HTTP_AUTHORIZATION' => bearer },
            params: {
              'collectionNames' => %w[user unknown],
              'timezone' => 'Europe/Paris'
            }
          }
          expect { capabilities_collections.handle_request(args) }.to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException, '🌳🌳🌳 Collection unknown not found.')
        end
      end
    end
  end
end
