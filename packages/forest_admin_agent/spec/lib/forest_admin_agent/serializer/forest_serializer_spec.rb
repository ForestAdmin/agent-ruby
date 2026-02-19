require 'spec_helper'
require 'singleton'

module ForestAdminAgent
  module Serializer
    include ForestAdminDatasourceToolkit
    include ForestAdminDatasourceToolkit::Schema
    include ForestAdminDatasourceToolkit::Schema::Relations
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

    describe ForestSerializer do
      describe 'relationships' do
        describe 'PolymorphicManyToOne serialization' do
          before do
            datasource = Datasource.new

            car_collection = build_collection(
              name: 'Car',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true, filter_operators: [Operators::EQUAL]),
                  'brand' => ColumnSchema.new(column_type: 'String')
                }
              }
            )

            user_collection = build_collection(
              name: 'User',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true, filter_operators: [Operators::EQUAL]),
                  'name' => ColumnSchema.new(column_type: 'String')
                }
              }
            )

            document_collection = build_collection(
              name: 'Document',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true, filter_operators: [Operators::EQUAL]),
                  'title' => ColumnSchema.new(column_type: 'String'),
                  'documentable_id' => ColumnSchema.new(column_type: 'Number'),
                  'documentable_type' => ColumnSchema.new(column_type: 'String'),
                  'documentable' => PolymorphicManyToOneSchema.new(
                    foreign_key: 'documentable_id',
                    foreign_key_type_field: 'documentable_type',
                    foreign_collections: %w[Car User],
                    foreign_key_targets: { 'Car' => 'id', 'User' => 'id' }
                  )
                }
              }
            )

            allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)
            datasource.add_collection(car_collection)
            datasource.add_collection(user_collection)
            datasource.add_collection(document_collection)
            ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(datasource)
            ForestAdminAgent::Builder::AgentFactory.instance.build
            @datasource = ForestAdminAgent::Facades::Container.datasource
          end

          it 'serializes a polymorphic belongs_to relation pointing to Car' do
            record = {
              'id' => 1,
              'title' => 'Registration Certificate',
              'documentable_id' => 10,
              'documentable_type' => 'Car',
              'documentable' => { 'id' => 10, 'brand' => 'Toyota' }
            }

            result = JSONAPI::Serializer.serialize(record, class_name: 'Document')

            relationship = result['data']['relationships']['documentable']
            expect(relationship['data']['type']).to eq('Car')
            expect(relationship['data']['id']).to eq('10')
          end

          it 'serializes a polymorphic belongs_to relation pointing to User' do
            record = {
              'id' => 2,
              'title' => 'ID Card',
              'documentable_id' => 5,
              'documentable_type' => 'User',
              'documentable' => { 'id' => 5, 'name' => 'John' }
            }

            result = JSONAPI::Serializer.serialize(record, class_name: 'Document')

            relationship = result['data']['relationships']['documentable']
            expect(relationship['data']['type']).to eq('User')
            expect(relationship['data']['id']).to eq('5')
          end
        end
      end
    end
  end
end
