require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Utils
    include ForestAdminDatasourceToolkit::Schema

    describe FieldPath do
      subject(:cards) { datasource.get_collection('cards') }

      let(:datasource) do
        build_datasource_with_collections(
          [
            build_collection(
              name: 'cards',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(is_primary_key: true, column_type: 'Number'),
                  'pan_last4' => ColumnSchema.new(column_type: 'String'),
                  'account_id' => ColumnSchema.new(column_type: 'Number'),
                  'holder_id' => ColumnSchema.new(column_type: 'Number'),
                  'account' => Relations::ManyToOneSchema.new(
                    foreign_collection: 'accounts', foreign_key: 'account_id', foreign_key_target: 'id'
                  ),
                  'certificate' => Relations::PolymorphicOneToOneSchema.new(
                    origin_key: 'owner_id',
                    origin_key_target: 'id',
                    foreign_collection: 'certificates',
                    origin_type_field: 'owner_type',
                    origin_type_value: 'Card'
                  ),
                  'holder' => Relations::PolymorphicManyToOneSchema.new(
                    foreign_key: 'holder_id',
                    foreign_key_type_field: 'holder_type',
                    foreign_collections: %w[persons companies],
                    foreign_key_targets: { 'persons' => 'id', 'companies' => 'id' }
                  )
                }
              }
            ),
            build_collection(
              name: 'accounts',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(is_primary_key: true, column_type: 'Number'),
                  'organization_id' => ColumnSchema.new(column_type: 'Number'),
                  'organization' => Relations::ManyToOneSchema.new(
                    foreign_collection: 'organizations', foreign_key: 'organization_id', foreign_key_target: 'id'
                  )
                }
              }
            ),
            build_collection(name: 'organizations', schema: { fields: { 'id' => ColumnSchema.new(is_primary_key: true, column_type: 'Number') } }),
            build_collection(name: 'certificates', schema: { fields: { 'id' => ColumnSchema.new(is_primary_key: true, column_type: 'Number') } }),
            build_collection(name: 'persons', schema: { fields: { 'id' => ColumnSchema.new(is_primary_key: true, column_type: 'Number') } }),
            build_collection(name: 'companies', schema: { fields: { 'id' => ColumnSchema.new(is_primary_key: true, column_type: 'Number') } })
          ]
        )
      end

      describe '.leaf_collection_names' do
        it 'answers the collection itself for one of its own columns' do
          expect(described_class.leaf_collection_names(cards, 'pan_last4')).to eq(['cards'])
        end

        it 'answers only the collection a path ends on, not the ones it crosses' do
          expect(described_class.leaf_collection_names(cards, 'account:organization:id')).to eq(['organizations'])
        end

        # No discriminant travels in the path, so a record may resolve to either target.
        it 'answers every target of a polymorphic many-to-one' do
          expect(described_class.leaf_collection_names(cards, 'holder:*')).to eq(%w[persons companies])
        end

        it 'answers the single target of a polymorphic one-to-one' do
          expect(described_class.leaf_collection_names(cards, 'certificate:id')).to eq(['certificates'])
        end

        # The caller pins the collection it asked about to readable, so falling back to it would turn
        # "this path does not resolve" into "this path is allowed".
        it 'raises rather than falling back when the prefix is a column' do
          expect { described_class.leaf_collection_names(cards, 'pan_last4:id') }.to raise_error(
            ForestAdminDatasourceToolkit::Exceptions::ForestException,
            "Relation not found: 'cards.pan_last4'"
          )
        end

        it 'raises when the prefix names nothing at all' do
          expect { described_class.leaf_collection_names(cards, 'unknown:id') }.to raise_error(
            ForestAdminDatasourceToolkit::Exceptions::ForestException,
            "Relation not found: 'cards.unknown'"
          )
        end
      end
    end
  end
end
