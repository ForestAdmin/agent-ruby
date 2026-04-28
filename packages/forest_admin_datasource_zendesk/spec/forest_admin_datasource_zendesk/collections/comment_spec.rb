RSpec.describe ForestAdminDatasourceZendesk::Collections::Comment do
  Filter = ForestAdminDatasourceToolkit::Components::Query::Filter
  Leaf   = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf
  Branch = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeBranch

  let(:client)     { instance_double(ForestAdminDatasourceZendesk::Client) }
  let(:datasource) { instance_double(ForestAdminDatasourceZendesk::Datasource, client: client) }
  let(:collection) { described_class.new(datasource) }

  describe 'schema' do
    it 'declares core comment fields and Author/Ticket ManyToOne relations' do
      keys = collection.schema[:fields].keys
      expect(keys).to include('id', 'ticket_id', 'author_id', 'body', 'public', 'author', 'ticket')
      expect(collection.schema[:fields]['author'])
        .to be_a(ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema)
    end

    it 'uses a synthetic single PK (String) to side-step forest_admin_rails URL constraints' do
      expect(collection.schema[:fields]['id'].is_primary_key).to be(true)
      expect(collection.schema[:fields]['id'].column_type).to eq('String')
      expect(collection.schema[:fields]['ticket_id'].is_primary_key).to be(false)
    end

    it 'leaves count disabled (Zendesk has no count endpoint for comments)' do
      expect(collection.is_countable?).to be(false)
    end
  end

  describe '#list' do
    it 'fetches comments by parent ticket_id (EQUAL); synthesizes id as <comment_id>-<ticket_id>' do
      expect(client).to receive(:fetch_ticket_comments).with(42).and_return([
                                                                              { 'id' => 1, 'body' => 'hi', 'author_id' => 7, 'public' => true,
                                                                                'created_at' => '2026-01-01' }
                                                                            ])

      filter = Filter.new(condition_tree: Leaf.new('ticket_id', 'equal', 42))
      result = collection.list(nil, filter, nil)
      expect(result.first).to include('id' => '1-42', 'body' => 'hi', 'ticket_id' => 42)
    end

    it 'fetches comments for every ticket_id in IN list' do
      allow(client).to receive(:fetch_ticket_comments).with(1).and_return([{ 'id' => 100 }])
      allow(client).to receive(:fetch_ticket_comments).with(2).and_return([{ 'id' => 200 }])

      filter = Filter.new(condition_tree: Leaf.new('ticket_id', 'in', [1, 2]))
      result = collection.list(nil, filter, ['id'])
      expect(result.map { |r| r['id'] }).to eq(['100-1', '200-2'])
    end

    it 'returns [] when filter targets a non-ticket_id field (top-level browse)' do
      expect(client).not_to receive(:fetch_ticket_comments)
      result = collection.list(nil,
                               Filter.new(condition_tree: Leaf.new('public', 'equal', true)), nil)
      expect(result).to eq([])
    end

    it 'returns [] when there is no condition tree at all (top-level browse)' do
      expect(client).not_to receive(:fetch_ticket_comments)
      expect(collection.list(nil, Filter.new, nil)).to eq([])
    end

    it 'returns [] when ticket_id uses an unsupported operator' do
      expect(client).not_to receive(:fetch_ticket_comments)
      filter = Filter.new(condition_tree: Leaf.new('ticket_id', 'greater_than', 1))
      expect(collection.list(nil, filter, nil)).to eq([])
    end

    it 'fetches a single comment via the synthetic id (show route: id = "<comment>-<ticket>")' do
      expect(client).to receive(:fetch_ticket_comments).with(226).and_return([
                                                                               { 'id' => 1, 'body' => 'first' },
                                                                               { 'id' => 2, 'body' => 'second' }
                                                                             ])

      filter = Filter.new(condition_tree: Leaf.new('id', 'equal', '2-226'))
      result = collection.list(nil, filter, nil)
      expect(result.size).to eq(1)
      expect(result.first['id']).to eq('2-226')
      expect(result.first['body']).to eq('second')
    end

    it 'returns [] when synthetic id is malformed (no dash)' do
      expect(client).not_to receive(:fetch_ticket_comments)
      filter = Filter.new(condition_tree: Leaf.new('id', 'equal', 'garbage'))
      expect(collection.list(nil, filter, nil)).to eq([])
    end

    it 'returns [] when only the comment_id half is invalid (e.g., "abc-456")' do
      # Regression: previously the malformed `abc-456` synthetic id
      # contributed its valid `456` ticket_id to the scope, then fetched ALL
      # comments for ticket 456 — wrong, because the row the user clicked
      # doesn't actually exist.
      expect(client).not_to receive(:fetch_ticket_comments)
      filter = Filter.new(condition_tree: Leaf.new('id', 'equal', 'abc-456'))
      expect(collection.list(nil, filter, nil)).to eq([])
    end

    it 'returns [] when only the ticket_id half is invalid (e.g., "1-bad")' do
      expect(client).not_to receive(:fetch_ticket_comments)
      filter = Filter.new(condition_tree: Leaf.new('id', 'equal', '1-bad'))
      expect(collection.list(nil, filter, nil)).to eq([])
    end

    it 'flattens via.channel into via_channel' do
      expect(client).to receive(:fetch_ticket_comments).with(1).and_return([
                                                                             { 'id' => 99,
                                                                               'via' => { 'channel' => 'web' } }
                                                                           ])

      filter = Filter.new(condition_tree: Leaf.new('ticket_id', 'equal', 1))
      result = collection.list(nil, filter, nil).first
      expect(result['via_channel']).to eq('web')
    end
  end
end
