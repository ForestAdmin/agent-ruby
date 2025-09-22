require 'spec_helper'

module ForestAdminAgent
  module Utils
    module Schema
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Schema
      describe GeneratorField do
        context 'when field is polymorphic relation' do
          before do
            collection_address = build_collection(
              name: 'Address',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                  'addressable_id' => ColumnSchema.new(column_type: 'Number'),
                  'addressable_type' => ColumnSchema.new(column_type: 'String'),
                  'addressable' => Relations::PolymorphicManyToOneSchema.new(
                    foreign_key_type_field: 'addressable_type',
                    foreign_collections: %w[User Order],
                    foreign_key_targets: { 'User' => 'id', 'Order' => 'id' },
                    foreign_key: 'addressable_id'
                  )
                }
              }
            )

            collection_user = build_collection(
              name: 'User',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                  'email' => ColumnSchema.new(column_type: 'String'),
                  'addresses' => Relations::PolymorphicOneToManySchema.new(
                    origin_key: 'addressable_id',
                    foreign_collection: 'Address',
                    origin_key_target: 'id',
                    origin_type_field: 'addressable_type',
                    origin_type_value: 'User'
                  )
                }
              }
            )

            collection_order = build_collection(
              name: 'Order',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                  'reference' => ColumnSchema.new(column_type: 'String'),
                  'address' => Relations::PolymorphicOneToOneSchema.new(
                    origin_key: 'addressable_id',
                    foreign_collection: 'Address',
                    origin_key_target: 'id',
                    origin_type_field: 'addressable_type',
                    origin_type_value: 'Order'
                  )
                }
              }
            )

            @datasource = build_datasource_with_collections(
              [collection_address, collection_order, collection_user]
            )
          end

          describe 'with a PolymorphicManyToOne' do
            it 'generate the relation' do
              schema = described_class.build_schema(@datasource.get_collection('Address'), 'addressable')

              expect(schema).to match(
                {
                  field: 'addressable',
                  inverseOf: 'Address',
                  reference: 'addressable.id',
                  relationship: 'BelongsTo',
                  type: 'Number',
                  defaultValue: nil,
                  enums: nil,
                  integration: nil,
                  isFilterable: false,
                  isPrimaryKey: false,
                  isReadOnly: false,
                  isRequired: false,
                  isSortable: false,
                  isVirtual: false,
                  validations: [],
                  polymorphic_referenced_models: %w[User Order]
                }
              )
            end
          end

          describe 'with a PolymorphicOneToOne' do
            it 'generate the relation' do
              schema = described_class.build_schema(@datasource.get_collection('Order'), 'address')

              expect(schema).to match(
                {
                  field: 'address',
                  inverseOf: 'addressable',
                  reference: 'Address.id',
                  relationship: 'HasOne',
                  type: 'Number',
                  defaultValue: nil,
                  enums: nil,
                  integration: nil,
                  isFilterable: false,
                  isPrimaryKey: false,
                  isReadOnly: false,
                  isRequired: false,
                  isSortable: false,
                  isVirtual: false,
                  validations: []
                }
              )
            end
          end

          describe 'with a PolymorphicOneToMany' do
            it 'generate the relation' do
              schema = described_class.build_schema(@datasource.get_collection('User'), 'addresses')

              expect(schema).to match(
                {
                  field: 'addresses',
                  inverseOf: 'addressable',
                  reference: 'Address.id',
                  relationship: 'HasMany',
                  type: ['Number'],
                  defaultValue: nil,
                  enums: nil,
                  integration: nil,
                  isFilterable: false,
                  isPrimaryKey: false,
                  isReadOnly: false,
                  isRequired: false,
                  isSortable: true,
                  isVirtual: false,
                  validations: []
                }
              )
            end
          end
        end
      end
    end
  end
end
