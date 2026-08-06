require 'spec_helper'

RSpec.describe ForestAdminDatasourceGraphqlHasura::Query::Aggregator do
  def scalar(name) = { 'name' => name, 'kind' => 'SCALAR' }
  def non_null(of_type) = { 'name' => nil, 'kind' => 'NON_NULL', 'ofType' => of_type }
  def list_of(of_type) = { 'name' => nil, 'kind' => 'LIST', 'ofType' => of_type }
  def object(name) = { 'name' => name, 'kind' => 'OBJECT' }
  def field(name, type) = { 'name' => name, 'type' => type }
  def list_query(table) = field(table, non_null(list_of(non_null(object(table)))))

  def by_pk_query(table)
    { 'name' => "#{table}_by_pk", 'type' => object(table),
      'args' => [{ 'name' => 'id', 'type' => non_null(scalar('bigint')) }] }
  end

  # payments.account_id is NOT NULL and its relationship rests on a real
  # foreign key constraint: no orphan row can exist.
  def stub_constrained_schema
    WebMock.stub_request(:post, BankingSchema::GRAPHQL_URI)
           .with { |request| request.body.include?('IntrospectSchema') }
           .to_return(
             status: 200,
             body: JSON.generate(
               { 'data' => { '__schema' => {
                 'types' => [
                   { 'name' => 'payments', 'kind' => 'OBJECT',
                     'fields' => [
                       field('id', non_null(scalar('bigint'))),
                       field('account_id', non_null(scalar('bigint'))),
                       field('account', object('accounts'))
                     ] },
                   { 'name' => 'accounts', 'kind' => 'OBJECT',
                     'fields' => [
                       field('id', non_null(scalar('bigint'))),
                       field('payments', non_null(list_of(non_null(object('payments')))))
                     ] }
                 ],
                 'queryType' => {
                   'name' => 'query_root',
                   'fields' => [list_query('payments'), by_pk_query('payments'),
                                list_query('accounts'), by_pk_query('accounts')]
                 }
               } } }
             ),
             headers: { 'Content-Type' => 'application/json' }
           )

    WebMock.stub_request(:post, BankingSchema::METADATA_URI)
           .to_return(
             status: 200,
             body: JSON.generate(
               { 'metadata' => { 'version' => 3, 'sources' => [
                 { 'name' => 'default', 'kind' => 'postgres', 'tables' => [
                   { 'table' => { 'schema' => 'public', 'name' => 'payments' },
                     'object_relationships' => [
                       { 'name' => 'account', 'using' => { 'foreign_key_constraint_on' => 'account_id' } }
                     ] },
                   { 'table' => { 'schema' => 'public', 'name' => 'accounts' },
                     'array_relationships' => [
                       { 'name' => 'payments',
                         'using' => { 'foreign_key_constraint_on' => {
                           'column' => 'account_id', 'table' => { 'schema' => 'public', 'name' => 'payments' }
                         } } }
                     ] }
                 ] }
               ] } }
             ),
             headers: { 'Content-Type' => 'application/json' }
           )
  end

  it 'skips the orphan query when the foreign key is NOT NULL and constraint-backed' do
    stub_constrained_schema
    datasource = ForestAdminDatasourceGraphqlHasura::Datasource.new(uri: BankingSchema::GRAPHQL_URI)
    BankingSchema.stub_graphql_data(
      { 'accounts' => [{ 'id' => 1, 'payments_aggregate' => { 'aggregate' => { 'count' => 2, 'row_count' => 2 } } }] }
    )

    aggregation = ForestAdminDatasourceToolkit::Components::Query::Aggregation.new(
      operation: 'Count', groups: [{ field: 'account_id' }]
    )
    result = datasource.get_collection('Payment')
                       .aggregate(nil, ForestAdminDatasourceToolkit::Components::Query::Filter.new, aggregation)

    expect(result).to eq([{ 'value' => 2, 'group' => { 'account_id' => 1 } }])
    expect(WebMock).to have_requested(:post, BankingSchema::GRAPHQL_URI)
      .with { |request| !request.body.include?('IntrospectSchema') }.once
  end
end
