require 'spec_helper'

RSpec.describe ForestAdminDatasourceGraphqlHasura::Collection do
  let(:datasource) { BankingSchema.build_datasource }
  let(:comments) { datasource.get_collection('Comment') }
  let(:caller) { nil }

  def toolkit_query
    ForestAdminDatasourceToolkit::Components::Query
  end

  def projection(*fields)
    toolkit_query::Projection.new(fields)
  end

  def filter(**options)
    toolkit_query::Filter.new(**options)
  end

  def leaf(field, operator, value = nil)
    toolkit_query::ConditionTree::Nodes::ConditionTreeLeaf.new(field, operator, value)
  end

  def branch(aggregator, conditions)
    toolkit_query::ConditionTree::Nodes::ConditionTreeBranch.new(aggregator, conditions)
  end

  def operators
    toolkit_query::ConditionTree::Operators
  end

  def graphql_requests
    requests = []
    expect(WebMock).to(have_requested(:post, BankingSchema::GRAPHQL_URI).at_least_once.with do |req|
      requests << JSON.parse(req.body) unless req.body.include?('IntrospectSchema')
      true
    end)
    requests
  end

  def last_graphql_request
    graphql_requests.last
  end

  describe '#list' do
    it 'selects the discriminator columns instead of joining the polymorphic targets' do
      BankingSchema.stub_graphql_data({ 'comments' => [] })

      comments.list(caller, filter, projection('id', 'body', 'commentable_type', 'commentable:*'))

      query = last_graphql_request['query']
      expect(query).to include('commentable_id')
      expect(query).to include('commentable_type')
      expect(query).not_to include('transfer {')
      expect(query).not_to include('card {')
    end

    it 'materializes the polymorphic relation as a phantom record' do
      BankingSchema.stub_graphql_data(
        {
          'comments' => [
            { 'id' => 1, 'body' => 'ok', 'commentable_type' => 'Transfer', 'commentable_id' => 42 },
            { 'id' => 2, 'body' => 'orphan', 'commentable_type' => nil, 'commentable_id' => nil }
          ]
        }
      )

      records = comments.list(caller, filter, projection('id', 'body', 'commentable_type', 'commentable:*'))

      expect(records[0]['commentable']).to eq({ '*' => nil })
      expect(records[0]['commentable_id']).to eq(42)
      expect(records[0]['commentable_type']).to eq('Transfer')
      expect(records[1]['commentable']).to be_nil
    end

    # A projection can reach a polymorphic relation through an ordinary one;
    # the nested records need their placeholders too.
    it 'materializes polymorphics on nested records' do
      BankingSchema.stub_graphql_data(
        {
          'transfers' => [
            { 'id' => 1,
              'comments' => [{ 'id' => 2, 'commentable_type' => 'Transfer', 'commentable_id' => 1 }] }
          ]
        }
      )

      transfers = datasource.get_collection('Transfer')
      records = transfers.list(caller, filter, projection('id', 'comments:id', 'comments:commentable:*'))

      expect(records[0]['comments'][0]['commentable']).to eq({ '*' => nil })
    end

    it 'resolves regular relations through Hasura nested selections' do
      BankingSchema.stub_graphql_data(
        { 'comments' => [{ 'id' => 1, 'membership' => { 'full_name' => 'Jane' } }] }
      )

      records = comments.list(caller, filter, projection('id', 'membership:full_name'))

      expect(last_graphql_request['query']).to include('membership { full_name }')
      expect(records[0]['membership']).to eq({ 'full_name' => 'Jane' })
    end

    it 'converts the related-data filter of a PolymorphicOneToMany into a flat bool_exp' do
      BankingSchema.stub_graphql_data({ 'comments' => [] })

      condition_tree = branch('And', [
                                leaf('commentable_id', operators::EQUAL, 42),
                                leaf('commentable_type', operators::EQUAL, 'Transfer')
                              ])
      comments.list(caller, filter(condition_tree: condition_tree), projection('id'))

      expect(last_graphql_request['variables']['where']).to eq(
        '_and' => [
          { 'commentable_id' => { '_eq' => 42 } },
          { 'commentable_type' => { '_eq' => 'Transfer' } }
        ]
      )
    end

    # `comments { }` is not valid GraphQL.
    it 'falls back to the primary key when the projection selects nothing' do
      BankingSchema.stub_graphql_data({ 'comments' => [] })

      comments.list(caller, filter, projection)

      expect(last_graphql_request['query']).to match(/comments\s*\{\s*id\s*\}/)
    end

    it 'applies sort and pagination' do
      BankingSchema.stub_graphql_data({ 'comments' => [] })

      list_filter = filter(
        sort: toolkit_query::Sort.new([{ field: 'created_at', ascending: false }]),
        page: toolkit_query::Page.new(offset: 10, limit: 5)
      )
      comments.list(caller, list_filter, projection('id'))

      variables = last_graphql_request['variables']
      expect(variables['orderBy']).to eq([{ 'created_at' => 'desc' }])
      expect(variables['limit']).to eq(5)
      expect(variables['offset']).to eq(10)
    end
  end

  describe '#create' do
    it 'inserts through Hasura and returns the created record' do
      BankingSchema.stub_graphql_data(
        { 'insert_comments' => { 'returning' => [{ 'id' => 7, 'body' => 'hello' }] } }
      )

      record = comments.create(caller, { 'body' => 'hello', 'membership_id' => 1 })

      expect(record).to eq({ 'id' => 7, 'body' => 'hello' })
      request = last_graphql_request
      expect(request['query']).to include('insert_comments(objects: $objects)')
      expect(request['variables']['objects']).to eq([{ 'body' => 'hello', 'membership_id' => 1 }])
    end

    # A column left empty must be written as null, not fall back to its database
    # default — same as the ActiveRecord datasource.
    it 'inserts an explicit nil instead of dropping the column' do
      BankingSchema.stub_graphql_data(
        { 'insert_comments' => { 'returning' => [{ 'id' => 7, 'body' => nil }] } }
      )

      comments.create(caller, { 'body' => nil, 'membership_id' => 1 })

      expect(last_graphql_request['variables']['objects']).to eq([{ 'body' => nil, 'membership_id' => 1 }])
    end

    it 'keeps a jsonb value on insert' do
      BankingSchema.stub_graphql_data(
        { 'insert_comments' => { 'returning' => [{ 'id' => 7 }] } }
      )

      comments.create(caller, { 'body' => 'x', 'metadata' => { 'source' => 'api' } })

      expect(last_graphql_request['variables']['objects'])
        .to eq([{ 'body' => 'x', 'metadata' => { 'source' => 'api' } }])
    end
  end

  describe '#update' do
    it 'refuses a filter whose condition tree matches everything' do
      empty_branch = branch('And', [])

      expect { comments.update(caller, filter(condition_tree: empty_branch), { 'body' => 'x' }) }
        .to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException, /Refusing/)
    end

    it 'updates through Hasura with the converted filter' do
      BankingSchema.stub_graphql_data({ 'update_comments' => { 'affected_rows' => 1 } })

      comments.update(caller, filter(condition_tree: leaf('id', operators::EQUAL, 7)), { 'body' => 'edited' })

      request = last_graphql_request
      expect(request['variables']['where']).to eq({ 'id' => { '_eq' => 7 } })
      expect(request['variables']['set']).to eq({ 'body' => 'edited' })
    end
  end

  describe '#delete' do
    it 'deletes through Hasura with the converted filter' do
      BankingSchema.stub_graphql_data({ 'delete_comments' => { 'affected_rows' => 1 } })

      comments.delete(caller, filter(condition_tree: leaf('id', operators::IN, [1, 2])))

      expect(last_graphql_request['variables']['where']).to eq({ 'id' => { '_in' => [1, 2] } })
    end
  end

  describe '#aggregate' do
    it 'rejects grouping on several fields rather than honouring only the first' do
      aggregation = toolkit_query::Aggregation.new(
        operation: 'Count',
        groups: [{ field: 'membership_id' }, { field: 'commentable_type' }]
      )

      expect { comments.aggregate(caller, filter, aggregation) }
        .to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException, /several fields/)
    end

    it 'merges parent rows that share the same group value' do
      BankingSchema.stub_graphql_data(
        {
          'memberships' => [
            { 'full_name' => 'Jane', 'comments_aggregate' => { 'aggregate' => { 'count' => 3 } } },
            { 'full_name' => 'Jane', 'comments_aggregate' => { 'aggregate' => { 'count' => 2 } } }
          ]
        }
      )

      aggregation = toolkit_query::Aggregation.new(operation: 'Count',
                                                   groups: [{ field: 'membership:full_name' }])
      result = comments.aggregate(caller, filter, aggregation)

      expect(result).to eq([{ 'value' => 5, 'group' => { 'membership:full_name' => 'Jane' } }])
    end

    # Hasura sends bigint as a string precisely because a Float would round it.
    it 'merges large integer sums without losing precision' do
      BankingSchema.stub_graphql_data(
        {
          'memberships' => [
            { 'full_name' => 'Jane',
              'comments_aggregate' => { 'aggregate' => { 'sum' => { 'id' => '9007199254740993' } } } },
            { 'full_name' => 'Jane', 'comments_aggregate' => { 'aggregate' => { 'sum' => { 'id' => '2' } } } }
          ]
        }
      )

      aggregation = toolkit_query::Aggregation.new(operation: 'Sum', field: 'id',
                                                   groups: [{ field: 'membership:full_name' }])
      result = comments.aggregate(caller, filter, aggregation)

      expect(result.first['value']).to eq(9_007_199_254_740_995)
    end

    # Two bigints that round to the same Float must not tie: the comparison has
    # to stay exact, or Max keeps whichever row came first.
    it 'merges a Max over bigints without float rounding ties' do
      BankingSchema.stub_graphql_data(
        {
          'memberships' => [
            { 'full_name' => 'Jane',
              'comments_aggregate' => { 'aggregate' => { 'max' => { 'id' => '9007199254740992' } } } },
            { 'full_name' => 'Jane',
              'comments_aggregate' => { 'aggregate' => { 'max' => { 'id' => '9007199254740993' } } } }
          ]
        }
      )

      aggregation = toolkit_query::Aggregation.new(operation: 'Max', field: 'id',
                                                   groups: [{ field: 'membership:full_name' }])
      result = comments.aggregate(caller, filter, aggregation)

      # Normalized to a number: a chart value should not be a string.
      expect(result.first['value']).to eq(9_007_199_254_740_993)
    end

    # A text value that happens to parse as a date must still compare lexically,
    # the way SQL collates a text column.
    it 'merges date-looking text lexically, not chronologically' do
      BankingSchema.stub_graphql_data(
        {
          'memberships' => [
            { 'full_name' => 'Jane',
              'comments_aggregate' => { 'aggregate' => { 'max' => { 'body' => '2 Jan 2021' } } } },
            { 'full_name' => 'Jane',
              'comments_aggregate' => { 'aggregate' => { 'max' => { 'body' => '3 Feb 2020' } } } }
          ]
        }
      )

      aggregation = toolkit_query::Aggregation.new(operation: 'Max', field: 'body',
                                                   groups: [{ field: 'membership:full_name' }])
      result = comments.aggregate(caller, filter, aggregation)

      expect(result.first['value']).to eq('3 Feb 2020')
    end

    # On a real date column, lexical ordering lies as soon as offsets differ.
    it 'merges a Max over a date column by instant' do
      BankingSchema.stub_graphql_data(
        {
          'memberships' => [
            { 'full_name' => 'Jane',
              'comments_aggregate' => { 'aggregate' => { 'max' => { 'created_at' => '2026-08-05T23:00:00+00:00' } } } },
            { 'full_name' => 'Jane',
              'comments_aggregate' => { 'aggregate' => { 'max' => { 'created_at' => '2026-08-06T00:30:00+02:00' } } } }
          ]
        }
      )

      aggregation = toolkit_query::Aggregation.new(operation: 'Max', field: 'created_at',
                                                   groups: [{ field: 'membership:full_name' }])
      result = comments.aggregate(caller, filter, aggregation)

      expect(result.first['value']).to eq('2026-08-05T23:00:00+00:00')
    end

    it 'rejects a relation as the aggregated field with a clear error' do
      aggregation = toolkit_query::Aggregation.new(operation: 'Sum', field: 'membership')

      expect { comments.aggregate(caller, filter, aggregation) }
        .to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException, /not a column/)
    end

    # `membership:comments` would emit a relation as a leaf selection.
    it 'rejects a group path ending on a relation with a clear error' do
      aggregation = toolkit_query::Aggregation.new(operation: 'Count',
                                                   groups: [{ field: 'membership:comments' }])

      expect { comments.aggregate(caller, filter, aggregation) }
        .to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException, /not a column/)
    end

    # Charting 0 in place of a value the wire format hid would be silently
    # wrong data.
    it 'raises on an aggregate value that cannot be read as a number' do
      BankingSchema.stub_graphql_data(
        { 'comments_aggregate' => { 'aggregate' => { 'sum' => { 'id' => 'NaN' }, 'row_count' => 2 } } }
      )

      aggregation = toolkit_query::Aggregation.new(operation: 'Sum', field: 'id')

      expect { comments.aggregate(caller, filter, aggregation) }
        .to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException, /Non-numeric/)
    end

    it 'merges a Max over text lexically instead of keeping the first row' do
      BankingSchema.stub_graphql_data(
        {
          'memberships' => [
            { 'full_name' => 'Jane', 'comments_aggregate' => { 'aggregate' => { 'max' => { 'body' => 'apple' } } } },
            { 'full_name' => 'Jane', 'comments_aggregate' => { 'aggregate' => { 'max' => { 'body' => 'pear' } } } }
          ]
        }
      )

      aggregation = toolkit_query::Aggregation.new(operation: 'Max', field: 'body',
                                                   groups: [{ field: 'membership:full_name' }])
      result = comments.aggregate(caller, filter, aggregation)

      expect(result.first['value']).to eq('pear')
    end

    # `count(columns: x)` returns zero when rows exist but every value is null,
    # which is not the same as a parent without children.
    it 'keeps a zero count on a specific column' do
      BankingSchema.stub_graphql_data(
        { 'memberships' => [{ 'id' => 1, 'comments_aggregate' => { 'aggregate' => { 'count' => 0 } } }] }
      )

      aggregation = toolkit_query::Aggregation.new(operation: 'Count', field: 'body',
                                                   groups: [{ field: 'membership_id' }])
      result = comments.aggregate(caller, filter, aggregation)

      expect(result).to eq([{ 'value' => 0, 'group' => { 'membership_id' => 1 } }])
    end

    # SQL keeps a group whose rows exist with the column all NULL (count 0, Sum
    # NULL), and omits a group with no rows: `row_count` tells them apart.
    it 'drops a parent without rows but keeps one whose aggregated column is all null' do
      BankingSchema.stub_graphql_data(
        {
          'memberships' => [
            { 'id' => 1, 'comments_aggregate' => { 'aggregate' => { 'count' => 0, 'row_count' => 0 } } },
            { 'id' => 2, 'comments_aggregate' => { 'aggregate' => { 'count' => 0, 'row_count' => 3 } } }
          ]
        }
      )

      aggregation = toolkit_query::Aggregation.new(operation: 'Count', field: 'body',
                                                   groups: [{ field: 'membership_id' }])
      result = comments.aggregate(caller, filter, aggregation)

      expect(result).to eq([{ 'value' => 0, 'group' => { 'membership_id' => 2 } }])
    end

    it 'keeps a null Sum group when its rows exist, sorted last' do
      BankingSchema.stub_graphql_data(
        {
          'memberships' => [
            { 'id' => 1,
              'comments_aggregate' => { 'aggregate' => { 'sum' => { 'id' => nil }, 'row_count' => 2 } } },
            { 'id' => 2,
              'comments_aggregate' => { 'aggregate' => { 'sum' => { 'id' => '7' }, 'row_count' => 1 } } }
          ]
        }
      )

      aggregation = toolkit_query::Aggregation.new(operation: 'Sum', field: 'id',
                                                   groups: [{ field: 'membership_id' }])
      result = comments.aggregate(caller, filter, aggregation)

      expect(result).to eq([
                             { 'value' => 7, 'group' => { 'membership_id' => 2 } },
                             { 'value' => nil, 'group' => { 'membership_id' => 1 } }
                           ])
    end

    # SQL Max ignores NULLs: a parent row whose values are all NULL must not win
    # the merge against a real value.
    it 'ignores null values when merging parents that share a group value' do
      BankingSchema.stub_graphql_data(
        {
          'memberships' => [
            { 'full_name' => 'Jane',
              'comments_aggregate' => { 'aggregate' => { 'max' => { 'body' => nil }, 'row_count' => 2 } } },
            { 'full_name' => 'Jane',
              'comments_aggregate' => { 'aggregate' => { 'max' => { 'body' => 'pear' }, 'row_count' => 1 } } }
          ]
        }
      )

      aggregation = toolkit_query::Aggregation.new(operation: 'Max', field: 'body',
                                                   groups: [{ field: 'membership:full_name' }])
      result = comments.aggregate(caller, filter, aggregation)

      expect(result.first['value']).to eq('pear')
    end

    it 'runs simple counts against <table>_aggregate' do
      BankingSchema.stub_graphql_data({ 'comments_aggregate' => { 'aggregate' => { 'count' => 12 } } })

      aggregation = toolkit_query::Aggregation.new(operation: 'Count')
      result = comments.aggregate(caller, filter, aggregation)

      expect(result).to eq([{ 'value' => 12, 'group' => {} }])
    end

    it 'groups on a foreign key through the parent nested aggregate' do
      BankingSchema.stub_graphql_data(
        {
          'memberships' => [
            { 'id' => 1, 'comments_aggregate' => { 'aggregate' => { 'count' => 3 } } },
            { 'id' => 2, 'comments_aggregate' => { 'aggregate' => { 'count' => 0 } } }
          ]
        }
      )

      aggregation = toolkit_query::Aggregation.new(operation: 'Count', groups: [{ field: 'membership_id' }])
      result = comments.aggregate(caller, filter, aggregation)

      expect(result).to eq([{ 'value' => 3, 'group' => { 'membership_id' => 1 } }])
    end

    it 'filters and orders the parent rows through the relationship predicate' do
      BankingSchema.stub_graphql_data({ 'memberships' => [] })

      aggregation = toolkit_query::Aggregation.new(operation: 'Count', groups: [{ field: 'membership_id' }])
      condition_tree = leaf('created_at', operators::GREATER_THAN, '2026-01-01')
      comments.aggregate(caller, filter(condition_tree: condition_tree), aggregation)

      parents_request = graphql_requests.find { |request| request['query'].include?('memberships(') }
      expect(parents_request['query']).to include('where: { comments: $where }')
      expect(parents_request['query']).to include('order_by: [{ id: asc }]')
      expect(parents_request['variables']['where']).to eq({ 'created_at' => { '_gt' => '2026-01-01' } })
    end

    it 'paginates the parent rows instead of stopping at the first page' do
      full_page = {
        'memberships' => (1..1000).map do |id|
          { 'id' => id, 'comments_aggregate' => { 'aggregate' => { 'count' => 1 } } }
        end
      }
      last_page = { 'memberships' => [{ 'id' => 2000, 'comments_aggregate' => { 'aggregate' => { 'count' => 5 } } }] }
      no_orphans = { 'comments_aggregate' => { 'aggregate' => { 'count' => 0 } } }
      BankingSchema.stub_graphql_data(full_page, last_page, no_orphans)

      aggregation = toolkit_query::Aggregation.new(operation: 'Count', groups: [{ field: 'membership_id' }])
      result = comments.aggregate(caller, filter, aggregation)

      expect(result.size).to eq(1001)
      expect(result.first).to eq({ 'value' => 5, 'group' => { 'membership_id' => 2000 } })
      offsets = graphql_requests.filter_map { |request| request.dig('variables', 'parentOffset') }
      expect(offsets).to eq([0, 1000])
    end

    it 'completes an aggregation spanning exactly the parent cap' do
      full_page = {
        'memberships' => (1..1000).map do |id|
          { 'id' => id, 'comments_aggregate' => { 'aggregate' => { 'count' => 1 } } }
        end
      }
      empty_page = { 'memberships' => [] }
      BankingSchema.stub_graphql_data(*Array.new(10, full_page), empty_page)

      aggregation = toolkit_query::Aggregation.new(operation: 'Count', groups: [{ field: 'membership_id' }])
      result = comments.aggregate(caller, filter, aggregation)

      # The ten identical pages merge into one group per id, each summing to 10.
      expect(result.size).to eq(1000)
      expect(result.first['value']).to eq(10)
    end

    it 'fails clearly instead of charting a subset when the parent rows exceed the cap' do
      full_page = {
        'memberships' => (1..1000).map do |id|
          { 'id' => id, 'comments_aggregate' => { 'aggregate' => { 'count' => 1 } } }
        end
      }
      BankingSchema.stub_graphql_data(*Array.new(10, full_page))

      aggregation = toolkit_query::Aggregation.new(operation: 'Count', groups: [{ field: 'membership_id' }])

      expect { comments.aggregate(caller, filter, aggregation) }
        .to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException, /more than 10000/)
    end

    # Grouping by the foreign key, SQL gives rows whose key is NULL a bucket of
    # their own; the parent-table detour cannot see them.
    it 'adds a bucket for the rows whose foreign key is null' do
      BankingSchema.stub_graphql_data(
        { 'memberships' => [{ 'id' => 1, 'comments_aggregate' => { 'aggregate' => { 'count' => 3 } } }] },
        { 'comments' => [] },
        { 'comments_aggregate' => { 'aggregate' => { 'count' => 2 } } }
      )

      aggregation = toolkit_query::Aggregation.new(operation: 'Count', groups: [{ field: 'membership_id' }])
      result = comments.aggregate(caller, filter, aggregation)

      expect(result).to eq([
                             { 'value' => 3, 'group' => { 'membership_id' => 1 } },
                             { 'value' => 2, 'group' => { 'membership_id' => nil } }
                           ])
      expect(last_graphql_request['variables']['where']).to eq({ 'membership_id' => { '_is_null' => true } })
    end

    # SQL keeps a dangling key (a value referencing no parent row) as a group of
    # its own when grouping by the foreign key — not merged into the NULL bucket.
    it 'keeps each dangling foreign key as its own group' do
      BankingSchema.stub_graphql_data(
        { 'memberships' => [{ 'id' => 1, 'comments_aggregate' => { 'aggregate' => { 'count' => 3 } } }] },
        { 'comments' => [{ 'membership_id' => 42 }] },
        { 'comments_aggregate' => { 'aggregate' => { 'count' => 5 } } },
        { 'comments_aggregate' => { 'aggregate' => { 'count' => 0, 'row_count' => 0 } } }
      )

      aggregation = toolkit_query::Aggregation.new(operation: 'Count', groups: [{ field: 'membership_id' }])
      result = comments.aggregate(caller, filter, aggregation)

      expect(result).to eq([
                             { 'value' => 5, 'group' => { 'membership_id' => 42 } },
                             { 'value' => 3, 'group' => { 'membership_id' => 1 } }
                           ])
      requests = graphql_requests
      expect(requests[1]['query']).to include('distinct_on: [membership_id]')
      expect(requests[2]['variables']['where']).to eq({ 'membership_id' => { '_eq' => 42 } })
    end

    # Grouping by a parent column, NULL and dangling keys alike are the NULL
    # group of a LEFT JOIN: one negated-relationship aggregate covers both.
    it 'adds a single null bucket when grouping through a parent column' do
      BankingSchema.stub_graphql_data(
        { 'memberships' => [{ 'full_name' => 'Jane',
                              'comments_aggregate' => { 'aggregate' => { 'count' => 3 } } }] },
        { 'comments_aggregate' => { 'aggregate' => { 'count' => 2 } } }
      )

      aggregation = toolkit_query::Aggregation.new(operation: 'Count',
                                                   groups: [{ field: 'membership:full_name' }])
      result = comments.aggregate(caller, filter, aggregation)

      expect(result).to include({ 'value' => 2, 'group' => { 'membership:full_name' => nil } })
      expect(last_graphql_request['variables']['where']).to eq({ '_not' => { 'membership' => {} } })
    end

    # `sum { }` would be an empty GraphQL selection set.
    it 'rejects a Sum without a field with a clear error' do
      aggregation = toolkit_query::Aggregation.new(operation: 'Sum')

      expect { comments.aggregate(caller, filter, aggregation) }
        .to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException, /requires a field/)
    end

    it 'enforces the cap even when the overflowing page is partial' do
      full_page = {
        'memberships' => (1..1000).map do |id|
          { 'id' => id, 'comments_aggregate' => { 'aggregate' => { 'count' => 1 } } }
        end
      }
      partial_page = {
        'memberships' => [{ 'id' => 10_500, 'comments_aggregate' => { 'aggregate' => { 'count' => 1 } } }]
      }
      BankingSchema.stub_graphql_data(*Array.new(10, full_page), partial_page)

      aggregation = toolkit_query::Aggregation.new(operation: 'Count', groups: [{ field: 'membership_id' }])

      expect { comments.aggregate(caller, filter, aggregation) }
        .to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException, /more than 10000/)
    end

    it 'rejects grouping on the polymorphic foreign key with a clear error' do
      aggregation = toolkit_query::Aggregation.new(operation: 'Count', groups: [{ field: 'commentable_id' }])

      expect { comments.aggregate(caller, filter, aggregation) }
        .to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException, /not supported/)
    end
  end
end
