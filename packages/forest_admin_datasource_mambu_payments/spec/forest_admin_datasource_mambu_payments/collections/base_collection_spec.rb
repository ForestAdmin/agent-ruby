module ForestAdminDatasourceMambuPayments
  Leaf = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf
  Branch = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeBranch

  RSpec.describe Collections::BaseCollection do
    let(:datasource) { instance_double(ForestAdminDatasourceMambuPayments::Datasource) }
    let(:collection) { Collections::ConnectedAccount.new(datasource) }

    describe '#extract_id_lookup' do
      it 'returns [value] for an id EQUAL leaf' do
        leaf = Leaf.new('id', 'equal', 'a')
        expect(collection.send(:extract_id_lookup, leaf)).to eq(['a'])
      end

      it 'returns the array for an id IN leaf' do
        leaf = Leaf.new('id', 'in', %w[a b])
        expect(collection.send(:extract_id_lookup, leaf)).to eq(%w[a b])
      end

      it 'wraps a scalar IN value into an array' do
        leaf = Leaf.new('id', 'in', 'a')
        expect(collection.send(:extract_id_lookup, leaf)).to eq(['a'])
      end

      it 'returns nil for a leaf on another field' do
        leaf = Leaf.new('name', 'equal', 'Acme')
        expect(collection.send(:extract_id_lookup, leaf)).to be_nil
      end

      it 'returns nil for an id leaf using an unsupported operator' do
        leaf = Leaf.new('id', 'present')
        expect(collection.send(:extract_id_lookup, leaf)).to be_nil
      end

      it 'returns nil for a Branch node (AND/OR not unwrapped)' do
        branch = Branch.new('And', [Leaf.new('id', 'equal', 'a')])
        expect(collection.send(:extract_id_lookup, branch)).to be_nil
      end

      it 'returns nil for a nil node' do
        expect(collection.send(:extract_id_lookup, nil)).to be_nil
      end
    end

    describe '#project' do
      let(:record) { { 'id' => '1', 'name' => 'Acme', 'extra' => 'x' } }

      it 'returns the record unchanged when projection is nil' do
        expect(collection.send(:project, record, nil)).to eq(record)
      end

      it 'keeps only the requested column fields' do
        result = collection.send(:project, record, %w[id name])
        expect(result).to eq('id' => '1', 'name' => 'Acme')
      end

      it 'drops projection entries containing a colon (relation prefixes)' do
        result = collection.send(:project, record, ['id', 'connected_account:name'])
        expect(result).to eq('id' => '1')
      end

      it 'returns an empty row when projection has only relation prefixes' do
        # Relations are populated by embed_relations; the scalar projection is
        # empty here, and returning the full record would leak unrequested columns.
        expect(collection.send(:project, record, ['connected_account:name'])).to eq({})
      end
    end

    describe '#translate_page' do
      it 'defaults to page 1 / MAX_PER_PAGE when no page is given' do
        expect(collection.send(:translate_page, nil))
          .to eq([1, ForestAdminDatasourceMambuPayments::Client::MAX_PER_PAGE])
      end

      it 'computes page number from offset / limit' do
        page = ForestAdminDatasourceToolkit::Components::Query::Page.new(limit: 10, offset: 20)
        expect(collection.send(:translate_page, page)).to eq([3, 10])
      end

      it 'caps the limit at MAX_PER_PAGE' do
        page = ForestAdminDatasourceToolkit::Components::Query::Page.new(limit: 999, offset: 0)
        _, per_page = collection.send(:translate_page, page)
        expect(per_page).to eq(ForestAdminDatasourceMambuPayments::Client::MAX_PER_PAGE)
      end
    end

    describe '#relations_in' do
      it 'returns the unique relation prefixes' do
        projection = ['id', 'name', 'connected_account:id', 'connected_account:name', 'foo:bar']
        expect(collection.send(:relations_in, projection)).to contain_exactly('connected_account', 'foo')
      end

      it 'returns [] when projection has only columns' do
        expect(collection.send(:relations_in, %w[id name])).to eq([])
      end

      it 'returns [] when projection is nil' do
        expect(collection.send(:relations_in, nil)).to eq([])
      end
    end

    describe '#embed_many_to_one' do
      let(:projection) { ['id', 'connected_account:name'] }
      let(:rows) { [{ 'id' => 't1' }, { 'id' => 't2' }, { 'id' => 't3' }] }
      let(:sources) do
        [
          { 'connected_account_id' => 'a' },
          { 'connected_account_id' => 'a' }, # dedup target
          { 'connected_account_id' => '' } # blank ignored
        ]
      end
      let(:batch_fetcher) { instance_double(Proc) }
      let(:serializer) { ->(raw) { { 'id' => raw['id'], 'name' => raw['name'] } } }

      it 'fetches the unique FKs in a single batch and assigns the serialized record' do
        allow(batch_fetcher).to receive(:call).with(['a']).and_return([{ 'id' => 'a', 'name' => 'Acme' }])

        collection.send(:embed_many_to_one, rows, sources, projection,
                        foreign_key: 'connected_account_id', relation_name: 'connected_account',
                        batch_fetcher: batch_fetcher, serializer: serializer)

        expect(rows[0]['connected_account']).to eq('id' => 'a', 'name' => 'Acme')
        expect(rows[1]['connected_account']).to eq('id' => 'a', 'name' => 'Acme')
        expect(rows[2]).not_to have_key('connected_account')
        expect(batch_fetcher).to have_received(:call).with(['a']).once
      end

      it 'does nothing when the projection does not request the relation' do
        allow(batch_fetcher).to receive(:call)

        collection.send(:embed_many_to_one, rows, sources, ['id'],
                        foreign_key: 'connected_account_id', relation_name: 'connected_account',
                        batch_fetcher: batch_fetcher, serializer: serializer)

        expect(rows).to all(satisfy { |r| !r.key?('connected_account') })
        expect(batch_fetcher).not_to have_received(:call)
      end

      it 'does nothing when projection is nil' do
        allow(batch_fetcher).to receive(:call)
        collection.send(:embed_many_to_one, rows, sources, nil,
                        foreign_key: 'connected_account_id', relation_name: 'connected_account',
                        batch_fetcher: batch_fetcher, serializer: serializer)
        expect(batch_fetcher).not_to have_received(:call)
      end

      it 'does nothing when no source has a usable FK' do
        allow(batch_fetcher).to receive(:call)

        empty_sources = [{ 'connected_account_id' => nil }, { 'connected_account_id' => '' }]
        collection.send(:embed_many_to_one, [{ 'id' => 'a' }, { 'id' => 'b' }], empty_sources, projection,
                        foreign_key: 'connected_account_id', relation_name: 'connected_account',
                        batch_fetcher: batch_fetcher, serializer: serializer)

        expect(batch_fetcher).not_to have_received(:call)
      end

      it 'leaves the relation nil for rows whose record is missing from the batch' do
        allow(batch_fetcher).to receive(:call).with(['a']).and_return([])

        collection.send(:embed_many_to_one, rows, sources, projection,
                        foreign_key: 'connected_account_id', relation_name: 'connected_account',
                        batch_fetcher: batch_fetcher, serializer: serializer)

        expect(rows[0]['connected_account']).to be_nil
        expect(rows[1]['connected_account']).to be_nil
      end
    end

    describe '#translate_filters' do
      it 'returns {} for a nil condition tree' do
        expect(collection.send(:translate_filters, nil)).to eq({})
      end

      it 'raises on a predicate the collection does not declare in api_filters' do
        leaf = Leaf.new('name', 'equal', 'Acme')
        expect { collection.send(:translate_filters, leaf) }
          .to raise_error(ForestAdminDatasourceMambuPayments::UnsupportedOperatorError)
      end

      it 'raises on a combined id predicate (Numeral has no list filter on id)' do
        # Pure-id leaves are served by the find-by-id short-circuit; an id ANDed
        # with another field would otherwise silently send an ignored param.
        leaf = Leaf.new('id', 'equal', 'x')
        expect { collection.send(:translate_filters, leaf) }
          .to raise_error(ForestAdminDatasourceMambuPayments::UnsupportedOperatorError)
      end
    end

    describe '#reconcile_filter_operators! (single source of truth for filters)' do
      it 'advertises only the operators api_filters can actually serve' do
        ops = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators
        f = collection.schema[:fields]
        # id is always filterable…
        expect(f['id'].filter_operators).to contain_exactly(ops::EQUAL, ops::IN)
        # …but a column absent from api_filters is not filterable at all, so the
        # UI never offers a filter that would raise at query time.
        expect(f['name'].filter_operators).to eq([])
      end
    end

    describe '#aggregate' do
      let(:client) { instance_double(ForestAdminDatasourceMambuPayments::Client) }
      let(:filter) { ForestAdminDatasourceToolkit::Components::Query::Filter.new }

      before { allow(datasource).to receive(:client).and_return(client) }

      it 'counts via the server-side total rather than listing records' do
        allow(client).to receive(:count_connected_accounts).and_return(4200)
        agg = ForestAdminDatasourceToolkit::Components::Query::Aggregation.new(operation: 'Count')
        expect(collection.aggregate(nil, filter, agg)).to eq([{ 'value' => 4200, 'group' => {} }])
      end

      it 'raises on non-Count aggregations' do
        agg = ForestAdminDatasourceToolkit::Components::Query::Aggregation.new(operation: 'Sum', field: 'amount')
        expect { collection.aggregate(nil, filter, agg) }
          .to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException, /Count/)
      end

      it 'raises on Count with groups' do
        agg = ForestAdminDatasourceToolkit::Components::Query::Aggregation.new(operation: 'Count',
                                                                               groups: [{ field: 'id' }])
        expect { collection.aggregate(nil, filter, agg) }
          .to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException)
      end
    end

    describe '#fetch_page over a window larger than one API page' do
      let(:client) { instance_double(ForestAdminDatasourceMambuPayments::Client) }
      let(:page_class) { ForestAdminDatasourceToolkit::Components::Query::Page }

      before { allow(datasource).to receive(:client).and_return(client) }

      it 'walks successive pages and slices to the requested [offset, offset + limit)' do
        full_page = Array.new(100) { |i| { 'id' => "p1-#{i}" } }
        second_page = Array.new(100) { |i| { 'id' => "p2-#{i}" } }
        allow(client).to receive(:list_connected_accounts).with(page: 1, limit: 100).and_return(full_page)
        allow(client).to receive(:list_connected_accounts).with(page: 2, limit: 100).and_return(second_page)

        rows = collection.send(:fetch_page, page_class.new(offset: 0, limit: 150), {})

        expect(rows.size).to eq(150)
        expect(rows.first['id']).to eq('p1-0')
        expect(rows.last['id']).to eq('p2-49')
      end
    end
  end
end
