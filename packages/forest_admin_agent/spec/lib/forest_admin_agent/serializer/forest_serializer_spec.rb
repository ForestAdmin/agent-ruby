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

            # Namespaced model (Admin::User => Admin__User) with a custom primary key
            admin_user_collection = build_collection(
              name: 'Admin__User',
              schema: {
                fields: {
                  'reference' => ColumnSchema.new(column_type: 'String', is_primary_key: true, filter_operators: [Operators::EQUAL]),
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
                    foreign_collections: %w[Car User Admin__User],
                    foreign_key_targets: { 'Car' => 'id', 'User' => 'id', 'Admin__User' => 'reference' }
                  )
                }
              }
            )

            allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)
            datasource.add_collection(car_collection)
            datasource.add_collection(user_collection)
            datasource.add_collection(admin_user_collection)
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

            result = JSONAPI::Serializer.serialize(record, class_name: 'Document', serializer: described_class)

            relationship = result['data']['relationships']['documentable']
            expect(relationship['data']['type']).to eq('Car')
            expect(relationship['data']['id']).to eq('10')
          end

          it 'builds the linkage id from the foreign key when the related record is a phantom (issue #332)' do
            # The AR datasource skips polymorphic relations while building the SELECT, so the related
            # object comes back without a primary key. The id must still be built from the owner FK.
            record = {
              'id' => 1,
              'title' => 'Registration Certificate',
              'documentable_id' => 10,
              'documentable_type' => 'Car',
              'documentable' => { '*' => nil }
            }

            result = JSONAPI::Serializer.serialize(record, class_name: 'Document', serializer: described_class)

            relationship = result['data']['relationships']['documentable']
            expect(relationship['data']['type']).to eq('Car')
            expect(relationship['data']['id']).to eq('10')
          end

          it 'builds the included document id and self-link from the foreign key (issue #332)' do
            record = {
              'id' => 1,
              'title' => 'Registration Certificate',
              'documentable_id' => 10,
              'documentable_type' => 'Car',
              'documentable' => { '*' => nil }
            }

            result = JSONAPI::Serializer.serialize(
              record, class_name: 'Document', serializer: described_class, include: 'documentable'
            )

            included = result['included'].find { |r| r['type'] == 'Car' }
            expect(included['id']).to eq('10')
            expect(included['links']['self']).to eq('/forest/Car/10')
          end

          it 'builds the linkage id for a namespaced target with a custom primary key (issue #332)' do
            # foreign_key_targets is keyed by the formatted name (Admin__User), but the type column
            # stores the raw class name (Admin::User); the lookup must reconcile the two.
            record = {
              'id' => 4,
              'title' => 'Audit Log',
              'documentable_id' => 'ref-42',
              'documentable_type' => 'Admin::User',
              'documentable' => { '*' => nil }
            }

            result = JSONAPI::Serializer.serialize(record, class_name: 'Document', serializer: described_class)

            relationship = result['data']['relationships']['documentable']
            expect(relationship['data']['type']).to eq('Admin__User')
            expect(relationship['data']['id']).to eq('ref-42')
          end

          it 'omits the data key for an unlinked polymorphic relation (issue #332)' do
            record = {
              'id' => 3,
              'title' => 'Orphan',
              'documentable_id' => nil,
              'documentable_type' => nil,
              'documentable' => { '*' => nil }
            }

            result = JSONAPI::Serializer.serialize(record, class_name: 'Document', serializer: described_class)

            expect(result['data']['relationships']['documentable']).not_to have_key('data')
          end

          it 'serializes a polymorphic belongs_to relation pointing to User' do
            record = {
              'id' => 2,
              'title' => 'ID Card',
              'documentable_id' => 5,
              'documentable_type' => 'User',
              'documentable' => { 'id' => 5, 'name' => 'John' }
            }

            result = JSONAPI::Serializer.serialize(record, class_name: 'Document', serializer: described_class)

            relationship = result['data']['relationships']['documentable']
            expect(relationship['data']['type']).to eq('User')
            expect(relationship['data']['id']).to eq('5')
          end
        end
      end
    end
  end
end
