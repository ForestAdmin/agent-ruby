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

    describe '#paginate (Numeral cursor pagination)' do
      let(:client) { instance_double(ForestAdminDatasourceMambuPayments::Client) }
      let(:page_class) { ForestAdminDatasourceToolkit::Components::Query::Page }

      before { allow(datasource).to receive(:client).and_return(client) }

      it 'fetches a single page sized to the request when it fits in one window' do
        allow(client).to receive(:list_connected_accounts).with(limit: 15).and_return(Array.new(15) { {} })

        collection.send(:paginate, page_class.new(offset: 0, limit: 15), {})

        expect(client).to have_received(:list_connected_accounts).with(limit: 15).once
      end

      it 'never asks Numeral for more than MAX_PER_PAGE in one call' do
        first = Array.new(100) { |i| { 'id' => "a#{i}" } }
        second = Array.new(50) { |i| { 'id' => "b#{i}" } }
        allow(client).to receive(:list_connected_accounts).with(limit: 100).and_return(first)
        allow(client).to receive(:list_connected_accounts).with(limit: 50, starting_after: 'a99').and_return(second)

        rows = collection.send(:paginate, page_class.new(offset: 0, limit: 150), {})

        expect(rows.size).to eq(150)
        expect(rows.last['id']).to eq('b49')
      end

      it 'walks the cursor to reach a non-zero offset and slices the window' do
        first = Array.new(100) { |i| { 'id' => "a#{i}" } }
        second = Array.new(20) { |i| { 'id' => "b#{i}" } }
        allow(client).to receive(:list_connected_accounts).with(limit: 100).and_return(first)
        allow(client).to receive(:list_connected_accounts).with(limit: 20, starting_after: 'a99').and_return(second)

        rows = collection.send(:paginate, page_class.new(offset: 110, limit: 10), {})

        expect(rows.map { |r| r['id'] }).to eq(%w[b10 b11 b12 b13 b14 b15 b16 b17 b18 b19])
      end

      it 'defaults to one MAX_PER_PAGE window when no page is given' do
        allow(client).to receive(:list_connected_accounts).with(limit: 100).and_return([])
        collection.send(:paginate, nil, {})
        expect(client).to have_received(:list_connected_accounts).with(limit: 100)
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
      let(:filter) { ForestAdminDatasourceToolkit::Components::Query::Filter.new }

      it 'is not supported (Numeral exposes no count/aggregate endpoint)' do
        agg = ForestAdminDatasourceToolkit::Components::Query::Aggregation.new(operation: 'Count')
        expect { collection.aggregate(nil, filter, agg) }
          .to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException, /not countable/)
      end

      it 'declares the collection non-countable so Forest never requests a count' do
        expect(collection.schema[:countable]).to be(false)
      end
    end
  end
end
