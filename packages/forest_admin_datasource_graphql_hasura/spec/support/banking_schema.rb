# Simulated Rails banking schema exposed through Hasura:
#
#   class Comment < ApplicationRecord
#     belongs_to :commentable, polymorphic: true   # commentable_type + commentable_id
#     belongs_to :membership
#   end
#   class Transfer < ApplicationRecord; has_many :comments, as: :commentable; end
#   class Card < ApplicationRecord;     has_many :comments, as: :commentable; end
module BankingSchema
  GRAPHQL_URI = 'http://hasura.test/v1/graphql'.freeze
  METADATA_URI = 'http://hasura.test/v1/metadata'.freeze

  module_function

  def scalar(name)
    { 'name' => name, 'kind' => 'SCALAR' }
  end

  def non_null(of_type)
    { 'name' => nil, 'kind' => 'NON_NULL', 'ofType' => of_type }
  end

  def list_of(of_type)
    { 'name' => nil, 'kind' => 'LIST', 'ofType' => of_type }
  end

  def object(name)
    { 'name' => name, 'kind' => 'OBJECT' }
  end

  def field(name, type)
    { 'name' => name, 'type' => type }
  end

  def list_query_field(table)
    field(table, non_null(list_of(non_null(object(table)))))
  end

  def by_pk_query_field(table)
    {
      'name' => "#{table}_by_pk",
      'type' => object(table),
      'args' => [{ 'name' => 'id', 'type' => non_null(scalar('bigint')) }]
    }
  end

  def introspection_response
    {
      'data' => {
        '__schema' => {
          'types' => [
            {
              'name' => 'comments',
              'kind' => 'OBJECT',
              'fields' => [
                field('id', non_null(scalar('bigint'))),
                field('body', scalar('String')),
                field('metadata', scalar('jsonb')),
                field('commentable_type', non_null(scalar('String'))),
                field('commentable_id', non_null(scalar('bigint'))),
                field('membership_id', scalar('bigint')),
                field('created_at', non_null(scalar('timestamptz'))),
                field('membership', object('memberships')),
                field('transfer', object('transfers')),
                field('card', object('cards'))
              ]
            },
            {
              'name' => 'transfers',
              'kind' => 'OBJECT',
              'fields' => [
                field('id', non_null(scalar('bigint'))),
                field('amount_cents', non_null(scalar('bigint'))),
                field('status', scalar('String')),
                field('comments', non_null(list_of(non_null(object('comments'))))),
                field('comments_aggregate', non_null(object('comments_aggregate')))
              ]
            },
            {
              'name' => 'cards',
              'kind' => 'OBJECT',
              'fields' => [
                field('id', non_null(scalar('bigint'))),
                field('last4', scalar('String')),
                field('comments', non_null(list_of(non_null(object('comments')))))
              ]
            },
            {
              'name' => 'memberships',
              'kind' => 'OBJECT',
              'fields' => [
                field('id', non_null(scalar('bigint'))),
                field('full_name', scalar('String')),
                field('comments', non_null(list_of(non_null(object('comments')))))
              ]
            }
          ],
          'queryType' => {
            'name' => 'query_root',
            'fields' => [
              list_query_field('comments'), by_pk_query_field('comments'),
              list_query_field('transfers'), by_pk_query_field('transfers'),
              list_query_field('cards'), by_pk_query_field('cards'),
              list_query_field('memberships'), by_pk_query_field('memberships')
            ]
          }
        }
      }
    }
  end

  def manual_object_relationship(name, remote_table, column_mapping)
    {
      'name' => name,
      'using' => {
        'manual_configuration' => {
          'remote_table' => { 'schema' => 'public', 'name' => remote_table },
          'column_mapping' => column_mapping
        }
      }
    }
  end

  def manual_array_relationship(name, remote_table, column_mapping)
    manual_object_relationship(name, remote_table, column_mapping)
  end

  # All a Rails team can declare in Hasura for a polymorphic belongs_to: one
  # manual relationship per target, joining on the foreign key alone, since a
  # column_mapping cannot carry the type condition.
  def metadata_response
    {
      'metadata' => {
        'version' => 3,
        'sources' => [
          {
            'name' => 'default',
            'kind' => 'postgres',
            'tables' => [
              {
                'table' => { 'schema' => 'public', 'name' => 'comments' },
                'object_relationships' => [
                  { 'name' => 'membership', 'using' => { 'foreign_key_constraint_on' => 'membership_id' } },
                  manual_object_relationship('transfer', 'transfers', { 'commentable_id' => 'id' }),
                  manual_object_relationship('card', 'cards', { 'commentable_id' => 'id' })
                ]
              },
              {
                'table' => { 'schema' => 'public', 'name' => 'transfers' },
                'array_relationships' => [
                  manual_array_relationship('comments', 'comments', { 'id' => 'commentable_id' })
                ]
              },
              {
                'table' => { 'schema' => 'public', 'name' => 'cards' },
                'array_relationships' => [
                  manual_array_relationship('comments', 'comments', { 'id' => 'commentable_id' })
                ]
              },
              {
                'table' => { 'schema' => 'public', 'name' => 'memberships' },
                'array_relationships' => [
                  {
                    'name' => 'comments',
                    'using' => {
                      'foreign_key_constraint_on' => {
                        'column' => 'membership_id',
                        'table' => { 'schema' => 'public', 'name' => 'comments' }
                      }
                    }
                  }
                ]
              }
            ]
          }
        ]
      }
    }
  end

  def stub_introspection
    WebMock::API.stub_request(:post, GRAPHQL_URI)
                .with { |request| request.body.include?('IntrospectSchema') }
                .to_return(status: 200, body: JSON.generate(introspection_response),
                           headers: { 'Content-Type' => 'application/json' })
  end

  def stub_metadata(available: true)
    if available
      WebMock::API.stub_request(:post, METADATA_URI)
                  .to_return(status: 200, body: JSON.generate(metadata_response),
                             headers: { 'Content-Type' => 'application/json' })
    else
      WebMock::API.stub_request(:post, METADATA_URI).to_return(status: 403, body: '{}')
    end
  end

  # Each argument is one response; WebMock repeats the last one when more
  # requests come in (a grouped aggregation issues parent pages, then the
  # null-bucket aggregate).
  def stub_graphql_data(*data)
    responses = data.map do |body|
      { status: 200, body: JSON.generate({ 'data' => body }),
        headers: { 'Content-Type' => 'application/json' } }
    end

    WebMock::API.stub_request(:post, GRAPHQL_URI)
                .with { |request| !request.body.include?('IntrospectSchema') }
                .to_return(*responses)
  end

  def build_datasource(**options)
    stub_introspection
    stub_metadata(available: !options.delete(:metadata_blocked))

    ForestAdminDatasourceGraphqlHasura::Datasource.new(uri: GRAPHQL_URI, **options)
  end
end
