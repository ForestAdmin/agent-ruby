require 'spec_helper'

module ForestAdminDatasourceRpc
  describe ReconciliateRpc do
    let(:plugin) { described_class.new }
    let(:collection_customizer) { instance_spy(ForestAdminDatasourceCustomizer::CollectionCustomizer) }

    describe '#add_relation' do
      context 'with ManyToOne relation' do
        it 'calls add_many_to_one_relation with correct options' do
          relation_definition = {
            type: 'ManyToOne',
            foreign_collection: 'Manufacturer',
            foreign_key: 'manufacturer_id',
            foreign_key_target: 'id'
          }

          plugin.send(:add_relation, collection_customizer, nil, 'manufacturer', relation_definition)

          expect(collection_customizer).to have_received(:add_many_to_one_relation).with(
            'manufacturer',
            'Manufacturer',
            { foreign_key: 'manufacturer_id', foreign_key_target: 'id' }
          )
        end

        it 'works with string keys' do
          relation_definition = {
            'type' => 'ManyToOne',
            'foreign_collection' => 'Manufacturer',
            'foreign_key' => 'manufacturer_id',
            'foreign_key_target' => 'id'
          }

          plugin.send(:add_relation, collection_customizer, nil, 'manufacturer', relation_definition)

          expect(collection_customizer).to have_received(:add_many_to_one_relation).with(
            'manufacturer',
            'Manufacturer',
            { foreign_key: 'manufacturer_id', foreign_key_target: 'id' }
          )
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

          plugin.send(:add_relation, collection_customizer, nil, 'products', relation_definition)

          expect(collection_customizer).to have_received(:add_one_to_many_relation).with(
            'products',
            'Product',
            { origin_key: 'manufacturer_id', origin_key_target: 'id' }
          )
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

          plugin.send(:add_relation, collection_customizer, nil, 'profile', relation_definition)

          expect(collection_customizer).to have_received(:add_one_to_one_relation).with(
            'profile',
            'Profile',
            { origin_key: 'user_id', origin_key_target: 'id' }
          )
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

          plugin.send(:add_relation, collection_customizer, nil, 'tags', relation_definition)

          expect(collection_customizer).to have_received(:add_many_to_many_relation).with(
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

          plugin.send(:add_relation, collection_customizer, renames, 'manufacturer', relation_definition)

          expect(collection_customizer).to have_received(:add_many_to_one_relation).with(
            'manufacturer',
            'RenamedManufacturer',
            { foreign_key: 'manufacturer_id', foreign_key_target: 'id' }
          )
        end

        it 'renames foreign_collection using Proc' do
          relation_definition = {
            type: 'ManyToOne',
            foreign_collection: 'Manufacturer',
            foreign_key: 'manufacturer_id',
            foreign_key_target: 'id'
          }
          renames = ->(name) { "Prefix_#{name}" }

          plugin.send(:add_relation, collection_customizer, renames, 'manufacturer', relation_definition)

          expect(collection_customizer).to have_received(:add_many_to_one_relation).with(
            'manufacturer',
            'Prefix_Manufacturer',
            { foreign_key: 'manufacturer_id', foreign_key_target: 'id' }
          )
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

          plugin.send(:add_relation, collection_customizer, renames, 'tags', relation_definition)

          expect(collection_customizer).to have_received(:add_many_to_many_relation).with(
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
        end
      end
    end
  end
end
