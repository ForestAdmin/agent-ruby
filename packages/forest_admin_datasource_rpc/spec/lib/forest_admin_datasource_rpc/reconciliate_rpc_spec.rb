require 'spec_helper'

module ForestAdminDatasourceRpc
  describe ReconciliateRpc do
    let(:plugin) { described_class.new }
    let(:collection_customizer) { instance_double(ForestAdminDatasourceCustomizer::CollectionCustomizer) }

    describe '#add_relation' do
      context 'with ManyToOne relation' do
        it 'calls add_many_to_one_relation with correct options' do
          relation_definition = {
            type: 'ManyToOne',
            foreign_collection: 'Manufacturer',
            foreign_key: 'manufacturer_id',
            foreign_key_target: 'id'
          }

          expect(collection_customizer).to receive(:add_many_to_one_relation).with(
            'manufacturer',
            'Manufacturer',
            { foreign_key: 'manufacturer_id', foreign_key_target: 'id' }
          )

          plugin.send(:add_relation, collection_customizer, nil, 'manufacturer', relation_definition)
        end

        it 'works with string keys' do
          relation_definition = {
            'type' => 'ManyToOne',
            'foreign_collection' => 'Manufacturer',
            'foreign_key' => 'manufacturer_id',
            'foreign_key_target' => 'id'
          }

          expect(collection_customizer).to receive(:add_many_to_one_relation).with(
            'manufacturer',
            'Manufacturer',
            { foreign_key: 'manufacturer_id', foreign_key_target: 'id' }
          )

          plugin.send(:add_relation, collection_customizer, nil, 'manufacturer', relation_definition)
        end
      end

      context 'with OneToMany relation' do
        it 'calls add_one_to_many_relation with correct options' do
          relation_definition = {
            type: 'OneToMany',
            foreign_collection: 'Product',
            origin_key: 'manufacturer_id',
            origin_key_target: 'id'
          }

          expect(collection_customizer).to receive(:add_one_to_many_relation).with(
            'products',
            'Product',
            { origin_key: 'manufacturer_id', origin_key_target: 'id' }
          )

          plugin.send(:add_relation, collection_customizer, nil, 'products', relation_definition)
        end
      end

      context 'with OneToOne relation' do
        it 'calls add_one_to_one_relation with correct options' do
          relation_definition = {
            type: 'OneToOne',
            foreign_collection: 'Profile',
            origin_key: 'user_id',
            origin_key_target: 'id'
          }

          expect(collection_customizer).to receive(:add_one_to_one_relation).with(
            'profile',
            'Profile',
            { origin_key: 'user_id', origin_key_target: 'id' }
          )

          plugin.send(:add_relation, collection_customizer, nil, 'profile', relation_definition)
        end
      end

      context 'with ManyToMany relation' do
        it 'calls add_many_to_many_relation with correct options' do
          relation_definition = {
            type: 'ManyToMany',
            foreign_collection: 'Tag',
            through_collection: 'ProductTag',
            foreign_key: 'tag_id',
            foreign_key_target: 'id',
            origin_key: 'product_id',
            origin_key_target: 'id'
          }

          expect(collection_customizer).to receive(:add_many_to_many_relation).with(
            'tags',
            'Tag',
            'ProductTag',
            {
              foreign_key: 'tag_id',
              foreign_key_target: 'id',
              origin_key: 'product_id',
              origin_key_target: 'id'
            }
          )

          plugin.send(:add_relation, collection_customizer, nil, 'tags', relation_definition)
        end
      end

      context 'with unsupported relation type' do
        it 'raises an error' do
          relation_definition = {
            type: 'InvalidType',
            foreign_collection: 'Something'
          }

          expect do
            plugin.send(:add_relation, collection_customizer, nil, 'invalid', relation_definition)
          end.to raise_error(
            ForestAdminDatasourceToolkit::Exceptions::ForestException,
            'Unsupported relation type: InvalidType'
          )
        end
      end

      context 'with rename option' do
        it 'renames foreign_collection using Hash' do
          relation_definition = {
            type: 'ManyToOne',
            foreign_collection: 'Manufacturer',
            foreign_key: 'manufacturer_id',
            foreign_key_target: 'id'
          }
          renames = { 'Manufacturer' => 'RenamedManufacturer' }

          expect(collection_customizer).to receive(:add_many_to_one_relation).with(
            'manufacturer',
            'RenamedManufacturer',
            { foreign_key: 'manufacturer_id', foreign_key_target: 'id' }
          )

          plugin.send(:add_relation, collection_customizer, renames, 'manufacturer', relation_definition)
        end

        it 'renames foreign_collection using Proc' do
          relation_definition = {
            type: 'ManyToOne',
            foreign_collection: 'Manufacturer',
            foreign_key: 'manufacturer_id',
            foreign_key_target: 'id'
          }
          renames = ->(name) { "Prefix_#{name}" }

          expect(collection_customizer).to receive(:add_many_to_one_relation).with(
            'manufacturer',
            'Prefix_Manufacturer',
            { foreign_key: 'manufacturer_id', foreign_key_target: 'id' }
          )

          plugin.send(:add_relation, collection_customizer, renames, 'manufacturer', relation_definition)
        end

        it 'renames through_collection for ManyToMany' do
          relation_definition = {
            type: 'ManyToMany',
            foreign_collection: 'Tag',
            through_collection: 'ProductTag',
            foreign_key: 'tag_id',
            foreign_key_target: 'id',
            origin_key: 'product_id',
            origin_key_target: 'id'
          }
          renames = { 'Tag' => 'RenamedTag', 'ProductTag' => 'RenamedProductTag' }

          expect(collection_customizer).to receive(:add_many_to_many_relation).with(
            'tags',
            'RenamedTag',
            'RenamedProductTag',
            {
              foreign_key: 'tag_id',
              foreign_key_target: 'id',
              origin_key: 'product_id',
              origin_key_target: 'id'
            }
          )

          plugin.send(:add_relation, collection_customizer, renames, 'tags', relation_definition)
        end
      end
    end
  end
end
