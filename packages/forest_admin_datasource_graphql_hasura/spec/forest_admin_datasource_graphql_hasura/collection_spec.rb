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

  def last_graphql_request
    request = nil
    expect(WebMock).to(have_requested(:post, BankingSchema::GRAPHQL_URI).at_least_once.with do |req|
      request = JSON.parse(req.body) unless req.body.include?('IntrospectSchema')
      true
    end)
    request
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

    it 'rejects grouping on the polymorphic foreign key with a clear error' do
      aggregation = toolkit_query::Aggregation.new(operation: 'Count', groups: [{ field: 'commentable_id' }])

      expect { comments.aggregate(caller, filter, aggregation) }
        .to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException, /not supported/)
    end
  end
end
