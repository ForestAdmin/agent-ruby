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
          let(:args) do
            {
              headers: { 'HTTP_AUTHORIZATION' => bearer },
              params: {
                'collectionNames' => [],
                'timezone' => 'Europe/Paris'
              }
            }
          end

          let(:result) { capabilities_collections.handle_request(args) }

          it 'returns no collection' do
            expect(result[:content][:collections].length).to eq(0)
          end

          it 'returns the correct fields and operators for the user collection' do
            user_collection = result[:content][:collections][0]
            expect(user_collection[:name]).to eq('user')

            user_fields = user_collection[:fields]
            expect(user_fields.length).to eq(3)
            expect(user_fields[0]).to include(name: 'id', type: 'Number')
            expect(user_fields[0][:operators]).to include('equal', 'greater_than', 'less_than', 'blank', 'in', 'missing')
          end

          it 'returns the correct fields and operators for the book collection' do
            book_collection = result[:content][:collections][1]
            expect(book_collection[:name]).to eq('book')

            book_fields = book_collection[:fields]
            expect(book_fields.length).to eq(5)
            expect(book_fields[0]).to include(name: 'id', type: 'Number')
            expect(book_fields[0][:operators]).to include('equal', 'blank', 'in', 'missing')
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
            expect(result[:content][:collections][0][:name]).to eq('user')
            fields = result[:content][:collections][0][:fields]
            expect(fields.length).to eq(3)

            expect(fields[0]).to include(name: 'id', type: 'Number')
            expect(fields[0][:operators]).to include('equal', 'greater_than', 'less_than', 'blank', 'in', 'missing')

            expect(fields[1]).to include(name: 'first_name', type: 'String')
            expect(fields[1][:operators]).to include('equal', 'present', 'in', 'missing')

            expect(fields[2]).to include(name: 'last_name', type: 'String')
            expect(fields[2][:operators]).to include('equal', 'present', 'in', 'missing')
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
