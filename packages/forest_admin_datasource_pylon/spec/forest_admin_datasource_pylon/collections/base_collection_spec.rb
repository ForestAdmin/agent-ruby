module ForestAdminDatasourcePylon
  RSpec.describe Collections::BaseCollection do
    def leaf(field, operator, value)
      ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf
        .new(field, operator, value)
    end

    def page(offset, limit)
      ForestAdminDatasourceToolkit::Components::Query::Page.new(offset: offset, limit: limit)
    end

    let(:operators) { ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators }

    let(:datasource) do
      instance_double(ForestAdminDatasourcePylon::Datasource,
                      client: instance_double(ForestAdminDatasourcePylon::Client))
    end

    let(:subclass) do
      Class.new(described_class) do
        def define_schema; end
        def define_relations; end

        public :extract_id_lookup, :project, :translate_page, :add_custom_fields
      end
    end

    let(:collection) { subclass.new(datasource, 'X') }

    describe 'subclass contract' do
      it 'raises NotImplementedError naming define_schema when the hook is missing' do
        expect { Class.new(described_class).new(datasource, 'X') }
          .to raise_error(NotImplementedError, /define_schema/)
      end

      it 'raises NotImplementedError naming define_relations when only define_schema is implemented' do
        incomplete = Class.new(described_class) { def define_schema; end }

        expect { incomplete.new(datasource, 'X') }.to raise_error(NotImplementedError, /define_relations/)
      end
    end

    describe 'search/count flags' do
      # Inverted from the Zendesk template: free-text search and Count land in
      # a later story, so a collection has to opt in rather than opt out.
      it 'leaves search and count disabled by default' do
        expect(collection.is_searchable?).to be(false)
        expect(collection.is_countable?).to be(false)
      end

      it 'honours searchable: true / countable: true from super' do
        opted_in = subclass.new(datasource, 'X', searchable: true, countable: true)

        expect(opted_in.is_searchable?).to be(true)
        expect(opted_in.is_countable?).to be(true)
      end
    end

    describe '#extract_id_lookup' do
      it 'extracts a single id from an equality leaf' do
        expect(collection.extract_id_lookup(leaf('id', operators::EQUAL, 'uuid-1'))).to eq(['uuid-1'])
      end

      it 'extracts every id from an in leaf' do
        node = leaf('id', operators::IN, %w[uuid-1 uuid-2])

        expect(collection.extract_id_lookup(node)).to eq(%w[uuid-1 uuid-2])
      end

      # Pylon ids are uuids: unlike Zendesk's integer ids, nothing is coerced.
      it 'keeps the id as an opaque string' do
        expect(collection.extract_id_lookup(leaf('id', operators::EQUAL, 42))).to eq(['42'])
      end

      it 'drops empty values' do
        expect(collection.extract_id_lookup(leaf('id', operators::IN, ['uuid-1', '']))).to eq(['uuid-1'])
      end

      it 'ignores a leaf on another field' do
        expect(collection.extract_id_lookup(leaf('state', operators::EQUAL, 'new'))).to be_nil
      end

      it 'ignores an operator the short-circuit cannot serve' do
        expect(collection.extract_id_lookup(leaf('id', operators::NOT_EQUAL, 'uuid-1'))).to be_nil
      end

      it 'ignores a nil condition tree' do
        expect(collection.extract_id_lookup(nil)).to be_nil
      end
    end

    describe '#project' do
      let(:record) { { 'id' => 'uuid-1', 'title' => 'Boom', 'state' => 'new' } }

      it 'returns the record untouched when there is no projection' do
        expect(collection.project(record, nil)).to eq(record)
      end

      it 'keeps only the projected fields' do
        expect(collection.project(record, %w[id title])).to eq('id' => 'uuid-1', 'title' => 'Boom')
      end

      it 'yields nil for a projected field the record does not carry' do
        expect(collection.project(record, %w[id missing])).to eq('id' => 'uuid-1', 'missing' => nil)
      end

      it 'ignores relation paths and returns the whole record when only those are asked for' do
        expect(collection.project(record, ['account:name'])).to eq(record)
      end
    end

    describe '#translate_page' do
      it 'defaults to a single full-size page when Forest sends none' do
        expect(collection.translate_page(nil)).to eq([0, Client::MAX_SEARCH_LIMIT])
      end

      it 'passes the offset and limit through' do
        expect(collection.translate_page(page(10, 25))).to eq([10, 25])
      end

      it 'falls back to the maximum limit when the page carries none' do
        expect(collection.translate_page(page(0, nil))).to eq([0, Client::MAX_SEARCH_LIMIT])
      end

      it 'clamps a negative offset to zero' do
        expect(collection.translate_page(page(-5, 10))).to eq([0, 10])
      end
    end

    describe '#add_custom_fields' do
      let(:schema) { ForestAdminDatasourceToolkit::Schema::ColumnSchema.new(column_type: 'String') }

      it 'adds a field and reports it as added' do
        added = collection.add_custom_fields([{ column_name: 'severity', schema: schema }])

        expect(added.map { |cf| cf[:column_name] }).to eq(['severity'])
        expect(collection.fields).to have_key('severity')
      end

      it 'skips a field colliding with an existing one and warns' do
        collection.add_field('severity', schema)
        allow(ForestAdminDatasourcePylon.logger).to receive(:warn)

        added = collection.add_custom_fields([{ column_name: 'severity', schema: schema }])

        expect(added).to be_empty
        expect(ForestAdminDatasourcePylon.logger).to have_received(:warn).with(/conflicts with an existing field/)
      end
    end
  end
end
