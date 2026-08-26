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
          add_field('account_id', column.new(column_type: 'String',
                                             filter_operators: [Collections::BaseCollection::Operators::IN]))
          add_field('owner_id', column.new(column_type: 'String'))
        end

        # Two ManyToOne, so the resolution can be observed on a relation whose
        # foreign key this collection filters and on one whose foreign key it
        # does not -- alongside a prefix naming no relation at all.
        def define_relations
          add_field('account', Collections::BaseCollection::ManyToOneSchema.new(
                                 foreign_collection: 'PylonAccount', foreign_key: 'account_id',
                                 foreign_key_target: 'id'
                               ))
          add_field('owner', Collections::BaseCollection::ManyToOneSchema.new(
                               foreign_collection: 'PylonUser', foreign_key: 'owner_id',
                               foreign_key_target: 'id'
                             ))
        end

        public :extract_id_lookup, :project, :translate_page, :add_custom_fields,
               :translate_sort, :timezone_for, :build_pylon_filter, :api_filters, :default_pk_sort?,
               :ensure_searchless_lookup!, :search_records, :page_window, :warn_unsortable,
               :with_resolved_relations
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

      # Count has no Pylon equivalent at all, so nothing opts into it: the
      # collections walking a cursor refuse `aggregate` outright, and the two
      # reading their whole dataset are not advertised as countable either.
      it 'honours searchable: true from super, count having no opt-in' do
        opted_in = subclass.new(datasource, 'X', searchable: true)

        expect(opted_in.is_searchable?).to be(true)
        expect(opted_in.is_countable?).to be(false)
      end
    end

    describe 'refusals' do
      # The agent answers 400 carrying the message for a ValidationError, and 500
      # "Unexpected error" for anything else. Every refusal of this datasource
      # names a filter the operator set and can change, and the message is the
      # only place they learn which one.
      it 'refuses through an error the agent answers 400 for' do
        expect(UnsupportedOperatorError.new('nope'))
          .to be_a(ForestAdminDatasourceToolkit::Exceptions::ValidationError)
      end

      # No Pylon endpoint aggregates, and a count over the pages the agent walked
      # would answer a fraction of the collection as if it were all of it. The
      # contract's NotImplementedError would read as an oversight instead.
      it 'refuses to aggregate, naming the collection' do
        expect { collection.aggregate(nil, nil, nil) }
          .to raise_error(UnsupportedOperatorError, /X cannot be aggregated/)
      end

      # A relation whose foreign key this collection does not filter cannot be
      # resolved: the keys read from the foreign collection would have nothing
      # to be matched against.
      it 'refuses a filter on a relation whose foreign key it cannot filter' do
        query = filter(condition_tree: leaf('owner:name', operators::EQUAL, 'Bob'))

        expect { collection.with_resolved_relations(nil, query) { |q| q } }
          .to raise_error(UnsupportedOperatorError,
                          /related field 'owner:name'.*Filter on 'owner_id' instead.*PylonUser list/m)
      end

      it 'refuses one whose prefix names no relation of the collection' do
        query = filter(condition_tree: leaf('nope:name', operators::EQUAL, 'Acme'))

        expect { collection.with_resolved_relations(nil, query) { |q| q } }
          .to raise_error(UnsupportedOperatorError, /Filter on a column of this collection instead/)
      end
    end

    # Pylon has no join, so a condition on a related field is answered by reading
    # the foreign collection for the keys matching it.
    describe '#with_resolved_relations' do
      let(:foreign) { instance_double(Collections::Account) }

      before { allow(datasource).to receive(:get_collection).with('PylonAccount').and_return(foreign) }

      def resolved(tree)
        collection.with_resolved_relations(nil, filter(condition_tree: tree), &:condition_tree)
      end

      def returning(*ids)
        allow(foreign).to receive(:list) { ids.map { |id| { 'id' => id } } }
      end

      it 'leaves a filter naming no relation untouched, without reading anything' do
        tree = leaf('state', operators::EQUAL, 'new')

        expect(resolved(tree)).to be(tree)
        expect(datasource).not_to have_received(:get_collection)
      end

      it 'rewrites the leaf into the foreign keys of the matching records' do
        returning('acc-1', 'acc-2')

        expect(resolved(leaf('account:name', operators::EQUAL, 'Acme')).to_h)
          .to eq(field: 'account_id', operator: operators::IN, value: %w[acc-1 acc-2])
      end

      # The condition reaches the foreign collection unnested, asking only for
      # the key it is matched against, and bounded so an overflow is seen.
      it 'reads the foreign collection for the target key alone' do
        returning('acc-1')
        resolved(leaf('account:name', operators::EQUAL, 'Acme'))

        expect(foreign).to have_received(:list) do |_caller, query, projection|
          expect(query.condition_tree.to_h).to eq(field: 'name', operator: operators::EQUAL, value: 'Acme')
          expect(query.page.to_h).to eq(offset: 0, limit: Collections::BaseCollection::MAX_RELATION_KEYS + 1)
          expect(projection).to eq(['id'])
        end
      end

      it 'resolves a relation nested inside a branch, leaving the other conditions in place' do
        returning('acc-1')
        tree = branch('And', [leaf('state', operators::EQUAL, 'new'), leaf('account:name', operators::EQUAL, 'Acme')])

        expect(resolved(tree).to_h[:conditions].last)
          .to eq(field: 'account_id', operator: operators::IN, value: %w[acc-1])
      end

      # No foreign record matched, so no record of this collection can: answered
      # without a request, rather than with an empty `in` reading as "everything".
      it 'answers with no record when nothing matched, without running the read' do
        returning
        ran = false
        query = filter(condition_tree: leaf('account:name', operators::EQUAL, 'Acme'))

        expect(collection.with_resolved_relations(nil, query) { ran = true }).to eq([])
        expect(ran).to be(false)
      end

      it 'empties an and whose relation matched nothing' do
        returning
        tree = branch('And', [leaf('state', operators::EQUAL, 'new'), leaf('account:name', operators::EQUAL, 'Acme')])

        expect(collection.with_resolved_relations(nil, filter(condition_tree: tree)) { |q| q }).to eq([])
      end

      # The other side of the union still selects records, so the unmatchable
      # branch drops out instead of emptying the read.
      it 'drops an unmatchable branch out of an or' do
        returning
        tree = branch('Or', [leaf('state', operators::EQUAL, 'new'), leaf('account:name', operators::EQUAL, 'Acme')])

        expect(resolved(tree).to_h)
          .to eq(aggregator: 'Or', conditions: [{ field: 'state', operator: operators::EQUAL, value: 'new' }])
      end

      it 'answers with no record when every branch of an or matched nothing' do
        returning
        tree = branch('Or', [leaf('account:name', operators::EQUAL, 'A'), leaf('account:name', operators::EQUAL, 'B')])

        expect(collection.with_resolved_relations(nil, filter(condition_tree: tree)) { |q| q }).to eq([])
      end

      # Truncating would answer a narrower question than the one asked, without
      # saying so.
      it 'refuses to truncate a relation matching more records than the cap' do
        returning(*Array.new(Collections::BaseCollection::MAX_RELATION_KEYS + 1) { |i| "acc-#{i}" })

        expect { resolved(leaf('account:name', operators::EQUAL, 'Acme')) }
          .to raise_error(UnsupportedOperatorError, /matches more than 500 PylonAccount records/)
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
          .to raise_error(UnsupportedOperatorError, /An id inside an `or` names none/)
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

      # The regression guarded here: a page-less read used to travel to the walk
      # as `limit: MAX_SEARCH_LIMIT`, which the walk could not tell from a window
      # the caller asked for — so it stopped at the first full page and answered a
      # larger set with its first thousand records, and did so without a warning.
      it 'follows the cursor past the first page when the filter carries no page' do
        collection = searching(search_page([{ 'id' => 'a' }], 'c1'),
                               search_page([{ 'id' => 'b' }], 'c2'),
                               search_page([{ 'id' => 'c' }]))

        expect(collection.search_records(nil, filter).map { |record| record['id'] }).to eq(%w[a b c])
        expect(collection.calls.map { |call| call[:cursor] }).to eq([nil, 'c1', 'c2'])
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

      # The relation is embedded onto the row afterwards; what `project` owns is
      # the columns, and a projection naming none asks for none. Serving the
      # whole record here would put every native column under a projection that
      # excluded them.
      it 'keeps no column when only relation paths are asked for' do
        expect(collection.project(record, ['account:name'])).to eq({})
      end

      it 'keeps the columns of a projection mixing the two' do
        expect(collection.project(record, ['id', 'account:name'])).to eq('id' => 'uuid-1')
      end
    end

    describe '#translate_page' do
      it 'asks for every record when Forest sends no page' do
        expect(collection.translate_page(nil)).to eq([0, nil])
      end

      it 'passes the offset and limit through' do
        expect(collection.translate_page(page(10, 25))).to eq([10, 25])
      end

      it 'asks for every record when the page carries no limit' do
        expect(collection.translate_page(page(0, nil))).to eq([0, nil])
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
