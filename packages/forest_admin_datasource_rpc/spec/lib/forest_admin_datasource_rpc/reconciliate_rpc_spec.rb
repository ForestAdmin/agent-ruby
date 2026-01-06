require 'spec_helper'

module ForestAdminDatasourceRpc
  describe ReconciliateRpc do
    let(:plugin) { described_class.new }
    let(:collection_customizer) { instance_spy(ForestAdminDatasourceCustomizer::CollectionCustomizer) }

    describe '#run' do
      let(:datasource_customizer) { double('DatasourceCustomizer') } # rubocop:disable RSpec/VerifiedDoubles
      let(:composite_datasource) { double('CompositeDatasource') } # rubocop:disable RSpec/VerifiedDoubles
      let(:rpc_datasource) { double('RpcDatasource') } # rubocop:disable RSpec/VerifiedDoubles
      let(:rpc_collection) { double('RpcCollection') } # rubocop:disable RSpec/VerifiedDoubles

      before do
        allow(datasource_customizer).to receive_messages(composite_datasource: composite_datasource, get_collection: collection_customizer)
      end

      context 'when datasource is not an RPC datasource' do
        let(:other_datasource) { instance_double(ForestAdminDatasourceToolkit::Datasource) }

        it 'skips non-RPC datasources' do
          allow(composite_datasource).to receive(:datasources).and_return([other_datasource])

          plugin.run(datasource_customizer)

          expect(datasource_customizer).not_to have_received(:get_collection)
        end
      end

      context 'when datasource is wrapped in decorators' do
        let(:decorator) { double('DatasourceDecorator') } # rubocop:disable RSpec/VerifiedDoubles

        before do
          allow(decorator).to receive(:is_a?).with(ForestAdminDatasourceToolkit::Decorators::DatasourceDecorator).and_return(true)
          allow(decorator).to receive(:child_datasource).and_return(rpc_datasource)
          allow(rpc_datasource).to receive(:is_a?).with(ForestAdminDatasourceToolkit::Decorators::DatasourceDecorator).and_return(false)
          allow(rpc_datasource).to receive(:is_a?).with(ForestAdminDatasourceRpc::Datasource).and_return(true)
          allow(rpc_datasource).to receive_messages(collections: {}, rpc_relations: nil)
          allow(composite_datasource).to receive(:datasources).and_return([decorator])
        end

        it 'unwraps decorators to find RPC datasource' do
          plugin.run(datasource_customizer)

          expect(decorator).to have_received(:child_datasource)
        end
      end

      context 'when collection is not searchable' do
        before do
          allow(rpc_datasource).to receive(:is_a?).with(ForestAdminDatasourceToolkit::Decorators::DatasourceDecorator).and_return(false)
          allow(rpc_datasource).to receive(:is_a?).with(ForestAdminDatasourceRpc::Datasource).and_return(true)
          allow(rpc_collection).to receive_messages(name: 'Product', schema: { searchable: false })
          allow(rpc_datasource).to receive_messages(collections: { 'Product' => rpc_collection }, rpc_relations: nil)
          allow(composite_datasource).to receive(:datasources).and_return([rpc_datasource])
        end

        it 'disables search on non-searchable collections' do
          plugin.run(datasource_customizer)

          expect(collection_customizer).to have_received(:disable_search)
        end
      end

      context 'when collection is searchable' do
        before do
          allow(rpc_datasource).to receive(:is_a?).with(ForestAdminDatasourceToolkit::Decorators::DatasourceDecorator).and_return(false)
          allow(rpc_datasource).to receive(:is_a?).with(ForestAdminDatasourceRpc::Datasource).and_return(true)
          allow(rpc_collection).to receive_messages(name: 'Product', schema: { searchable: true })
          allow(rpc_datasource).to receive_messages(collections: { 'Product' => rpc_collection }, rpc_relations: nil)
          allow(composite_datasource).to receive(:datasources).and_return([rpc_datasource])
        end

        it 'does not disable search on searchable collections' do
          plugin.run(datasource_customizer)

          expect(collection_customizer).not_to have_received(:disable_search)
        end
      end

      context 'when rpc_relations exist' do
        before do
          allow(rpc_datasource).to receive(:is_a?).with(ForestAdminDatasourceToolkit::Decorators::DatasourceDecorator).and_return(false)
          allow(rpc_datasource).to receive(:is_a?).with(ForestAdminDatasourceRpc::Datasource).and_return(true)
          allow(rpc_datasource).to receive_messages(
            collections: {},
            rpc_relations: {
              'Product' => {
                'manufacturer' => { type: 'ManyToOne', foreign_collection: 'Manufacturer', foreign_key: 'manufacturer_id', foreign_key_target: 'id' }
              }
            }
          )
          allow(composite_datasource).to receive(:datasources).and_return([rpc_datasource])
        end

        it 'adds relations from rpc_relations' do
          plugin.run(datasource_customizer)

          expect(collection_customizer).to have_received(:add_many_to_one_relation).with(
            'manufacturer',
            'Manufacturer',
            { foreign_key: 'manufacturer_id', foreign_key_target: 'id' }
          )
        end
      end

      context 'with rename option' do
        before do
          allow(rpc_datasource).to receive(:is_a?).with(ForestAdminDatasourceToolkit::Decorators::DatasourceDecorator).and_return(false)
          allow(rpc_datasource).to receive(:is_a?).with(ForestAdminDatasourceRpc::Datasource).and_return(true)
          allow(rpc_collection).to receive_messages(name: 'Product', schema: { searchable: false })
          allow(rpc_datasource).to receive_messages(collections: { 'Product' => rpc_collection }, rpc_relations: nil)
          allow(composite_datasource).to receive(:datasources).and_return([rpc_datasource])
        end

        it 'uses renamed collection name with Hash' do
          plugin.run(datasource_customizer, nil, { rename: { 'Product' => 'RenamedProduct' } })

          expect(datasource_customizer).to have_received(:get_collection).with('RenamedProduct')
        end

        it 'uses renamed collection name with Proc' do
          plugin.run(datasource_customizer, nil, { rename: ->(name) { "Prefix_#{name}" } })

          expect(datasource_customizer).to have_received(:get_collection).with('Prefix_Product')
        end
      end
    end

    describe '#get_collection_name' do
      it 'returns original name when renames is nil' do
        result = plugin.send(:get_collection_name, nil, 'Product')

        expect(result).to eq('Product')
      end

      it 'returns original name when renames Hash does not contain the key' do
        result = plugin.send(:get_collection_name, { 'Other' => 'RenamedOther' }, 'Product')

        expect(result).to eq('Product')
      end

      it 'returns renamed name when renames Hash contains the key' do
        result = plugin.send(:get_collection_name, { 'Product' => 'RenamedProduct' }, 'Product')

        expect(result).to eq('RenamedProduct')
      end

      it 'returns renamed name when renames is a Proc' do
        result = plugin.send(:get_collection_name, ->(name) { "Prefix_#{name}" }, 'Product')

        expect(result).to eq('Prefix_Product')
      end

      it 'handles symbol collection name with string Hash key' do
        result = plugin.send(:get_collection_name, { 'Product' => 'RenamedProduct' }, :Product)

        expect(result).to eq('RenamedProduct')
      end
    end

    describe '#get_datasource' do
      it 'returns datasource as-is when not a decorator' do
        datasource = double('Datasource') # rubocop:disable RSpec/VerifiedDoubles
        allow(datasource).to receive(:is_a?).with(ForestAdminDatasourceToolkit::Decorators::DatasourceDecorator).and_return(false)

        result = plugin.send(:get_datasource, datasource)

        expect(result).to eq(datasource)
      end

      it 'unwraps single decorator' do
        inner_datasource = double('InnerDatasource') # rubocop:disable RSpec/VerifiedDoubles
        decorator = double('Decorator') # rubocop:disable RSpec/VerifiedDoubles

        allow(decorator).to receive(:is_a?).with(ForestAdminDatasourceToolkit::Decorators::DatasourceDecorator).and_return(true)
        allow(decorator).to receive(:child_datasource).and_return(inner_datasource)
        allow(inner_datasource).to receive(:is_a?).with(ForestAdminDatasourceToolkit::Decorators::DatasourceDecorator).and_return(false)

        result = plugin.send(:get_datasource, decorator)

        expect(result).to eq(inner_datasource)
      end

      it 'unwraps nested decorators' do
        inner_datasource = double('InnerDatasource') # rubocop:disable RSpec/VerifiedDoubles
        inner_decorator = double('InnerDecorator') # rubocop:disable RSpec/VerifiedDoubles
        outer_decorator = double('OuterDecorator') # rubocop:disable RSpec/VerifiedDoubles

        allow(outer_decorator).to receive(:is_a?).with(ForestAdminDatasourceToolkit::Decorators::DatasourceDecorator).and_return(true)
        allow(outer_decorator).to receive(:child_datasource).and_return(inner_decorator)
        allow(inner_decorator).to receive(:is_a?).with(ForestAdminDatasourceToolkit::Decorators::DatasourceDecorator).and_return(true)
        allow(inner_decorator).to receive(:child_datasource).and_return(inner_datasource)
        allow(inner_datasource).to receive(:is_a?).with(ForestAdminDatasourceToolkit::Decorators::DatasourceDecorator).and_return(false)

        result = plugin.send(:get_datasource, outer_decorator)

        expect(result).to eq(inner_datasource)
      end
    end

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
