module ForestAdminDatasourcePylon
  RSpec.describe Collections::BaseCollection do
    def leaf(field, operator, value)
      ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf
        .new(field, operator, value)
    end

    def branch(aggregator, conditions)
      ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeBranch
        .new(aggregator, conditions)
    end

    def filter(condition_tree: nil, search: nil, page: nil)
      ForestAdminDatasourceToolkit::Components::Query::Filter.new(
        condition_tree: condition_tree, search: search, page: page
      )
    end

    def page(offset, limit)
      ForestAdminDatasourceToolkit::Components::Query::Page.new(offset: offset, limit: limit)
    end

    def sort(field, ascending: true)
      ForestAdminDatasourceToolkit::Components::Query::Sort.new([{ field: field, ascending: ascending }])
    end

    let(:operators) { ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators }

    let(:datasource) do
      instance_double(ForestAdminDatasourcePylon::Datasource,
                      client: instance_double(ForestAdminDatasourcePylon::Client))
    end

    let(:subclass) do
      Class.new(described_class) do
        # Minimal schema: the residual guard looks the columns up, and the
        # default-sort check needs a primary key to compare against.
        def define_schema
          column = Collections::BaseCollection::ColumnSchema
          add_field('id', column.new(column_type: 'String', is_primary_key: true))
          add_field('state', column.new(column_type: 'String'))
          add_field('type', column.new(column_type: 'String'))
          add_field('tags', column.new(column_type: 'Json'))
          add_field('resolved_at', column.new(column_type: 'Date'))
        end

        def define_relations; end

        public :extract_id_lookup, :project, :translate_page, :add_custom_fields,
               :translate_sort, :timezone_for, :build_pylon_filter, :api_filters, :default_pk_sort?,
               :ensure_searchless_lookup!, :search_records, :page_window, :warn_unsortable
      end
    end

    # Implements the two hooks the read pipeline leaves to the collection: one
    # page of the cursor walk, and the serialization of what it collected.
    let(:searching_subclass) do
      Class.new(subclass) do
        attr_accessor :pages
        attr_reader :calls

        # A field the endpoint filters, so the translated filter handed to
        # `search_page` can be observed.
        def api_filters
          operators = Collections::BaseCollection::Operators
          { 'state' => { ops: { operators::EQUAL => 'equals' } } }
        end

        protected

        def search_page(limit:, cursor:, filter:, search_text:)
          @calls ||= []
          @calls << { limit: limit, cursor: cursor, filter: filter, search_text: search_text }
          @pages.shift || Client::SearchPage.new(records: [], next_cursor: nil)
        end

        private

        def serialize(record) = record.merge('serialized' => true)
      end
    end

    let(:collection) { subclass.new(datasource, 'X') }

    def searching(*pages)
      searching_subclass.new(datasource, 'X').tap { |collection| collection.pages = pages }
    end

    def search_page(records, next_cursor = nil)
      Client::SearchPage.new(records: records, next_cursor: next_cursor)
    end

    describe 'subclass contract' do
      it 'raises NotImplementedError naming define_schema when the hook is missing' do
        expect { Class.new(described_class).new(datasource, 'X') }
          .to raise_error(NotImplementedError, /define_schema/)
      end

      it 'raises NotImplementedError naming define_relations when only define_schema is implemented' do
        incomplete = Class.new(described_class) { def define_schema; end }

        expect { incomplete.new(datasource, 'X') }.to raise_error(NotImplementedError, /define_relations/)
      end

      it 'raises NotImplementedError naming search_page when the walk reaches the endpoint hook' do
        expect { collection.search_records(nil, filter) }.to raise_error(NotImplementedError, /search_page/)
      end

      # Reached only by a collection declaring a ManyToOne to this one: an
      # unresolvable relation names the missing hook rather than embedding nil.
      it 'raises NotImplementedError naming records_indexed_by_id when a relation points here' do
        expect { collection.records_indexed_by_id(%w[uuid-1]) }
          .to raise_error(NotImplementedError, /records_indexed_by_id/)
      end
    end

    describe 'search/count flags' do
      # Inverted from the Zendesk template: only the endpoints that really carry
      # `search_text` opt in, and Count has no Pylon equivalent at all.
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
        lookup = collection.extract_id_lookup(leaf('id', operators::EQUAL, 'uuid-1'))

        expect(lookup.ids).to eq(['uuid-1'])
        expect(lookup.residual).to be_nil
      end

      it 'extracts every id from an in leaf' do
        node = leaf('id', operators::IN, %w[uuid-1 uuid-2])

        expect(collection.extract_id_lookup(node).ids).to eq(%w[uuid-1 uuid-2])
      end

      # Pylon ids are uuids: unlike Zendesk's integer ids, nothing is coerced.
      it 'keeps the id as an opaque string' do
        expect(collection.extract_id_lookup(leaf('id', operators::EQUAL, 42)).ids).to eq(['42'])
      end

      it 'drops empty values' do
        expect(collection.extract_id_lookup(leaf('id', operators::IN, ['uuid-1', ''])).ids).to eq(['uuid-1'])
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

      # Forest sends `AND(id equal X, <scope>)` on a record detail as soon as a
      # scope or a segment is set, and `id` is not a Pylon filter field.
      it 'pulls the id out of a top-level and, returning the other conditions' do
        scope = leaf('state', operators::EQUAL, 'new')
        lookup = collection.extract_id_lookup(branch('And', [leaf('id', operators::EQUAL, 'uuid-1'), scope]))

        expect(lookup.ids).to eq(['uuid-1'])
        expect(lookup.residual.to_h).to eq(scope.to_h)
      end

      it 'keeps the remaining conditions grouped when more than one is left' do
        conditions = [leaf('id', operators::IN, %w[uuid-1]), leaf('state', operators::EQUAL, 'new'),
                      leaf('type', operators::EQUAL, 'ticket')]

        residual = collection.extract_id_lookup(branch('And', conditions)).residual

        expect(residual.to_h).to eq(aggregator: 'And', conditions: conditions.drop(1).map(&:to_h))
      end

      it 'reports no residual when the and carries the id alone' do
        lookup = collection.extract_id_lookup(branch('And', [leaf('id', operators::EQUAL, 'uuid-1')]))

        expect(lookup.residual).to be_nil
      end

      # An OR cannot be narrowed to the ids: the other side of the union would
      # bring in records the short-circuit never fetched.
      it 'ignores an id nested in an or' do
        node = branch('Or', [leaf('id', operators::EQUAL, 'uuid-1'), leaf('state', operators::EQUAL, 'new')])

        expect(collection.extract_id_lookup(node)).to be_nil
      end

      it 'ignores an and carrying no id condition' do
        node = branch('And', [leaf('state', operators::EQUAL, 'new'), leaf('type', operators::EQUAL, 'ticket')])

        expect(collection.extract_id_lookup(node)).to be_nil
      end

      # A Json column holds a list whose Pylon membership semantics have no
      # in-memory counterpart: the lookup is refused rather than mis-filtered.
      it 'refuses a lookup whose residual it cannot evaluate in memory' do
        node = branch('And', [leaf('id', operators::EQUAL, 'uuid-1'), leaf('tags', operators::CONTAINS, 'vip')])

        expect { collection.extract_id_lookup(node) }
          .to raise_error(UnsupportedOperatorError, /cannot be combined with a primary-key lookup/)
      end

      it 'refuses a residual on a field the schema does not declare' do
        node = branch('And', [leaf('id', operators::EQUAL, 'uuid-1'), leaf('ghost', operators::EQUAL, 'x')])

        expect { collection.extract_id_lookup(node) }
          .to raise_error(UnsupportedOperatorError, /field 'ghost'/)
      end

      # `ConditionTreeLeaf#match` compares with a bare `>`, which raises a
      # NoMethodError on the nil Pylon returns for an unresolved issue. The
      # guard pairs the comparison with a presence check, the way a database
      # excludes a NULL row from a comparison.
      describe 'guarding a comparison against a null column' do
        let(:comparison) { leaf('resolved_at', operators::GREATER_THAN, '2026-01-01T00:00:00Z') }
        let(:residual) do
          collection.extract_id_lookup(branch('And', [leaf('id', operators::EQUAL, 'uuid-1'), comparison])).residual
        end

        it 'pairs the comparison with a presence check' do
          expect(residual.to_h).to eq(
            aggregator: 'And',
            conditions: [{ field: 'resolved_at', operator: operators::PRESENT, value: nil }, comparison.to_h]
          )
        end

        it 'excludes the record instead of raising when the column is null' do
          expect { residual.apply([{ 'id' => 'uuid-1', 'resolved_at' => nil }], collection, 'UTC') }
            .not_to raise_error
          expect(residual.apply([{ 'id' => 'uuid-1', 'resolved_at' => nil }], collection, 'UTC')).to eq([])
        end

        it 'still keeps a record the comparison matches' do
          record = { 'id' => 'uuid-1', 'resolved_at' => '2026-08-07T13:06:22Z' }

          expect(residual.apply([record], collection, 'UTC')).to eq([record])
        end

        it 'leaves an operator that needs no guard untouched' do
          equality = leaf('state', operators::EQUAL, 'new')
          node = branch('And', [leaf('id', operators::EQUAL, 'uuid-1'), equality])

          expect(collection.extract_id_lookup(node).residual.to_h).to eq(equality.to_h)
        end
      end
    end

    describe '#ensure_searchless_lookup!' do
      # Pylon searches through its search endpoint, which cannot filter on id,
      # and reads an id through its own, which cannot search: honouring both at
      # once is impossible, and honouring one silently is what this refuses.
      it 'refuses a lookup carrying a free-text search' do
        expect { collection.ensure_searchless_lookup!(filter(search: 'boom')) }
          .to raise_error(UnsupportedOperatorError, /search cannot be combined with a filter on 'id'/)
      end

      it 'accepts a lookup carrying no search' do
        expect { collection.ensure_searchless_lookup!(filter) }.not_to raise_error
        expect { collection.ensure_searchless_lookup!(nil) }.not_to raise_error
        expect { collection.ensure_searchless_lookup!(filter(search: '  ')) }.not_to raise_error
      end
    end

    describe '#default_pk_sort?' do
      # The agent injects this exact sort whenever the request asks for no order.
      it 'recognises the ascending primary-key sort the agent injects' do
        expect(collection.default_pk_sort?(sort('id'))).to be(true)
      end

      it 'does not mistake a chosen order for the default' do
        expect(collection.default_pk_sort?(sort('id', ascending: false))).to be(false)
        expect(collection.default_pk_sort?(sort('state'))).to be(false)
      end
    end

    describe '#translate_sort' do
      let(:allow_list) { { 'created_at' => 'created_at' } }

      it 'maps an allowed field to its api name and direction' do
        expect(collection.translate_sort(sort('created_at'), allow_list)).to eq(%w[created_at asc])
        expect(collection.translate_sort(sort('created_at', ascending: false), allow_list))
          .to eq(%w[created_at desc])
      end

      it 'reports no sort for a field outside the allow-list' do
        expect(collection.translate_sort(sort('title'), allow_list)).to eq([nil, nil])
      end

      it 'reports no sort when Forest asks for none' do
        expect(collection.translate_sort(nil, allow_list)).to eq([nil, nil])
        expect(collection.translate_sort([], allow_list)).to eq([nil, nil])
      end

      it 'reads a plain hash clause as well as a Sort entry' do
        expect(collection.translate_sort([{ field: 'created_at', ascending: false }], allow_list))
          .to eq(%w[created_at desc])
        expect(collection.translate_sort([{ 'field' => 'created_at', 'ascending' => true }], allow_list))
          .to eq(%w[created_at asc])
      end
    end

    describe '#timezone_for' do
      it 'falls back to UTC when the caller carries no timezone' do
        expect(collection.timezone_for(nil)).to eq('UTC')
        expect(collection.timezone_for(instance_double(ForestAdminDatasourceToolkit::Components::Caller,
                                                       timezone: nil))).to eq('UTC')
        expect(collection.timezone_for(instance_double(ForestAdminDatasourceToolkit::Components::Caller,
                                                       timezone: ''))).to eq('UTC')
      end

      it 'uses the timezone of the caller' do
        caller = instance_double(ForestAdminDatasourceToolkit::Components::Caller, timezone: 'Europe/Paris')

        expect(collection.timezone_for(caller)).to eq('Europe/Paris')
      end
    end

    describe '#build_pylon_filter' do
      # A collection that declares nothing filterable is the safe default: every
      # predicate is refused rather than silently dropped.
      it 'declares no server-side filter by default' do
        expect(collection.api_filters).to eq({})
        expect { collection.build_pylon_filter(nil, filter(condition_tree: leaf('state', operators::EQUAL, 'new'))) }
          .to raise_error(ForestAdminDatasourcePylon::UnsupportedOperatorError, /cannot filter on 'state'/)
      end

      it 'returns no filter when there is no condition tree' do
        expect(collection.build_pylon_filter(nil, filter)).to be_nil
        expect(collection.build_pylon_filter(nil, nil)).to be_nil
      end

      # The UI offers both an `id equals` filter and the and/or toggle, so this
      # is reachable by an operator and deserves better than the translator's
      # "add it to the collection's api_filters".
      it 'reports an id the short-circuit could not reach with an actionable error' do
        node = branch('Or', [leaf('id', operators::EQUAL, 'uuid-1'), leaf('state', operators::EQUAL, 'new')])

        expect { collection.build_pylon_filter(nil, filter(condition_tree: node)) }
          .to raise_error(UnsupportedOperatorError, /has to be combined with 'and' conditions only/)
      end

      # A collection whose endpoint filters id server-side never short-circuits,
      # so there is nothing an `or` could widen: id is translated like any other
      # field, including under an aggregator.
      it 'translates an id the collection declares in api_filters, even inside an or' do
        filtering = Class.new(subclass) do
          def api_filters
            operators = Collections::BaseCollection::Operators
            { 'id' => { ops: { operators::EQUAL => 'equals' } },
              'state' => { ops: { operators::EQUAL => 'equals' } } }
          end
        end.new(datasource, 'X')
        node = branch('Or', [leaf('id', operators::EQUAL, 'uuid-1'), leaf('state', operators::EQUAL, 'new')])

        expect(filtering.build_pylon_filter(nil, filter(condition_tree: node))).to eq(
          'operator' => 'or',
          'subfilters' => [{ 'field' => 'id', 'operator' => 'equals', 'value' => 'uuid-1' },
                           { 'field' => 'state', 'operator' => 'equals', 'value' => 'new' }]
        )
      end
    end

    describe '#search_records' do
      it 'walks a single page and serializes what it collected' do
        collection = searching(search_page([{ 'id' => 'a' }, { 'id' => 'b' }]))

        expect(collection.search_records(nil, filter))
          .to eq([{ 'id' => 'a', 'serialized' => true }, { 'id' => 'b', 'serialized' => true }])
        expect(collection.calls)
          .to eq([{ limit: Client::MAX_SEARCH_LIMIT, cursor: nil, filter: nil, search_text: nil }])
      end

      # The walker asks for the window still missing and hands back the cursor of
      # the previous page; the filter and the search stay the same throughout.
      it 'follows the cursor until the requested window is covered' do
        collection = searching(search_page([{ 'id' => 'a' }, { 'id' => 'b' }], 'c1'),
                               search_page([{ 'id' => 'c' }]))
        query = filter(condition_tree: leaf('state', operators::EQUAL, 'new'), search: 'boom', page: page(2, 1))

        expect(collection.search_records(nil, query)).to eq([{ 'id' => 'c', 'serialized' => true }])
        expect(collection.calls).to eq(
          [{ limit: 3, cursor: nil, filter: { 'field' => 'state', 'operator' => 'equals', 'value' => 'new' },
             search_text: 'boom' },
           { limit: 1, cursor: 'c1', filter: { 'field' => 'state', 'operator' => 'equals', 'value' => 'new' },
             search_text: 'boom' }]
        )
      end

      it 'refuses a predicate the endpoint cannot express instead of searching unfiltered' do
        collection = searching(search_page([{ 'id' => 'a' }]))

        expect { collection.search_records(nil, filter(condition_tree: leaf('type', operators::EQUAL, 'x'))) }
          .to raise_error(UnsupportedOperatorError, /cannot filter on 'type'/)
        expect(collection.calls).to be_nil
      end
    end

    describe '#page_window' do
      let(:records) { [{ 'id' => 'a' }, { 'id' => 'b' }, { 'id' => 'c' }] }

      it 'slices the requested window out of the records' do
        expect(collection.page_window(records, filter(page: page(1, 1)))).to eq([{ 'id' => 'b' }])
      end

      it 'returns every record when Forest asks for no page' do
        expect(collection.page_window(records, nil)).to eq(records)
      end

      it 'reports an empty window rather than nil past the last record' do
        expect(collection.page_window(records, filter(page: page(10, 5)))).to eq([])
      end
    end

    describe '#warn_unsortable' do
      before { allow(ForestAdminDatasourcePylon.logger).to receive(:warn) }

      # The empty default matches an endpoint exposing no sort parameter: the
      # order is reported instead of being silently swallowed.
      it 'reports a chosen order the collection cannot honour, naming it' do
        collection.warn_unsortable(sort('state'))

        expect(ForestAdminDatasourcePylon.logger)
          .to have_received(:warn).with('[forest_admin_datasource_pylon] X cannot honour the requested order.')
      end

      it 'stays quiet on no order and on the default primary-key sort the agent injects' do
        collection.warn_unsortable(nil)
        collection.warn_unsortable([])
        collection.warn_unsortable(sort('id'))

        expect(ForestAdminDatasourcePylon.logger).not_to have_received(:warn)
      end

      it 'stays quiet on an order the endpoint does sort by' do
        sorting = Class.new(subclass) { def sortable_fields = { 'state' => 'state' } }.new(datasource, 'X')

        sorting.warn_unsortable(sort('state'))

        expect(ForestAdminDatasourcePylon.logger).not_to have_received(:warn)
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

      # The safe default matches the empty api_filters: a collection that
      # filters nothing server-side must not advertise custom-field filters
      # either, or the translator would refuse at query time what the schema
      # offered.
      it 'clamps the declared operators to the collection allow-list and warns' do
        allow(ForestAdminDatasourcePylon.logger).to receive(:warn)
        declared = ForestAdminDatasourceToolkit::Schema::ColumnSchema
                   .new(column_type: 'String', filter_operators: [operators::EQUAL])

        added = collection.add_custom_fields([{ column_name: 'severity', schema: declared }])

        expect(collection.fields['severity'].filter_operators).to eq([])
        expect(added.first[:schema].filter_operators).to eq([])
        expect(ForestAdminDatasourcePylon.logger)
          .to have_received(:warn).with(/cannot honour on a custom field \(equal\)/)
      end

      it 'clamps a copy, leaving the integrator schema object untouched' do
        allow(ForestAdminDatasourcePylon.logger).to receive(:warn)
        declared = ForestAdminDatasourceToolkit::Schema::ColumnSchema
                   .new(column_type: 'String', filter_operators: [operators::EQUAL])

        collection.add_custom_fields([{ column_name: 'severity', schema: declared }])

        expect(declared.filter_operators).to eq([operators::EQUAL])
      end
    end
  end
end
