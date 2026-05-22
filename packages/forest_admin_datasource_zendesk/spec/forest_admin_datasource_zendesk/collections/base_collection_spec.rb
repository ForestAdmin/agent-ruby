module ForestAdminDatasourceZendesk
  RSpec.describe Collections::BaseCollection do
    let(:datasource) do
      instance_double(ForestAdminDatasourceZendesk::Datasource,
                      client: instance_double(ForestAdminDatasourceZendesk::Client),
                      custom_field_mapping: {})
    end

    describe 'subclass contract' do
      it 'raises NotImplementedError naming define_schema when the hook is missing' do
        subclass = Class.new(described_class)
        expect { subclass.new(datasource, 'X') }
          .to raise_error(NotImplementedError, /define_schema/)
      end

      it 'raises NotImplementedError naming define_relations when only define_schema is implemented' do
        subclass = Class.new(described_class) { def define_schema; end }
        expect { subclass.new(datasource, 'X') }
          .to raise_error(NotImplementedError, /define_relations/)
      end
    end

    describe 'search/count opt-out' do
      let(:subclass) do
        Class.new(described_class) do
          def define_schema; end
          def define_relations; end
        end
      end

      it 'enables search and count by default' do
        collection = subclass.new(datasource, 'X')
        expect(collection.is_searchable?).to be(true)
        expect(collection.is_countable?).to be(true)
      end

      it 'honours searchable: false / countable: false from super' do
        collection = subclass.new(datasource, 'X', searchable: false, countable: false)
        expect(collection.is_searchable?).to be(false)
        expect(collection.is_countable?).to be(false)
      end
    end
  end
end
