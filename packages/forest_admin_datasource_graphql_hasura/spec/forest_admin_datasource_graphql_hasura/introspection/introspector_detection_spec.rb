require 'spec_helper'

RSpec.describe ForestAdminDatasourceGraphqlHasura::Introspection::Introspector do
  def scalar(name) = { 'name' => name, 'kind' => 'SCALAR' }
  def enum(name) = { 'name' => name, 'kind' => 'ENUM' }
  def non_null(of_type) = { 'name' => nil, 'kind' => 'NON_NULL', 'ofType' => of_type }
  def list_of(of_type) = { 'name' => nil, 'kind' => 'LIST', 'ofType' => of_type }
  def object(name) = { 'name' => name, 'kind' => 'OBJECT' }
  def field(name, type) = { 'name' => name, 'type' => type }

  def list_query(table) = field(table, non_null(list_of(non_null(object(table)))))

  def by_pk_query(table, pk_names = ['id'])
    {
      'name' => "#{table}_by_pk",
      'type' => object(table),
      'args' => pk_names.map { |name| { 'name' => name, 'type' => non_null(scalar('bigint')) } }
    }
  end

  def fk_object_rel(name, column)
    { 'name' => name, 'using' => { 'foreign_key_constraint_on' => column } }
  end

  def manual_object_rel(name, remote_table, mapping, schema: 'public')
    {
      'name' => name,
      'using' => {
        'manual_configuration' => {
          'remote_table' => { 'schema' => schema, 'name' => remote_table },
          'column_mapping' => mapping
        }
      }
    }
  end

  def stub_schema(types, query_fields)
    WebMock.stub_request(:post, BankingSchema::GRAPHQL_URI)
           .with { |request| request.body.include?('IntrospectSchema') }
           .to_return(
             status: 200,
             body: JSON.generate({ 'data' => { '__schema' => {
                                   'types' => types,
                                   'queryType' => { 'name' => 'query_root', 'fields' => query_fields }
                                 } } }),
             headers: { 'Content-Type' => 'application/json' }
           )
  end

  def stub_metadata(tables)
    WebMock.stub_request(:post, BankingSchema::METADATA_URI)
           .to_return(
             status: 200,
             body: JSON.generate({ 'metadata' => { 'version' => 3, 'sources' => [
                                   { 'name' => 'default', 'kind' => 'postgres', 'tables' => tables }
                                 ] } }),
             headers: { 'Content-Type' => 'application/json' }
           )
  end

  def build_datasource(**options)
    ForestAdminDatasourceGraphqlHasura::Datasource.new(uri: BankingSchema::GRAPHQL_URI, **options)
  end

  describe 'a business enum sitting next to a real foreign key' do
    before do
      stub_schema(
        [
          {
            'name' => 'payments', 'kind' => 'OBJECT',
            'fields' => [
              field('id', non_null(scalar('bigint'))),
              field('account_type', non_null(scalar('String'))),
              field('account_id', non_null(scalar('bigint'))),
              field('account', object('accounts'))
            ]
          },
          {
            'name' => 'accounts', 'kind' => 'OBJECT',
            'fields' => [
              field('id', non_null(scalar('bigint'))),
              field('iban', scalar('String')),
              field('payments', non_null(list_of(non_null(object('payments')))))
            ]
          }
        ],
        [list_query('payments'), by_pk_query('payments'), list_query('accounts'), by_pk_query('accounts')]
      )

      stub_metadata(
        [
          {
            'table' => { 'schema' => 'public', 'name' => 'payments' },
            'object_relationships' => [fk_object_rel('account', 'account_id')]
          },
          {
            'table' => { 'schema' => 'public', 'name' => 'accounts' },
            'array_relationships' => [
              { 'name' => 'payments',
                'using' => { 'foreign_key_constraint_on' => {
                  'column' => 'account_id', 'table' => { 'schema' => 'public', 'name' => 'payments' }
                } } }
            ]
          }
        ]
      )
    end

    it 'does not turn a real foreign key next to a <base>_type enum into a polymorphic relation' do
      fields = build_datasource.get_collection('Payment').schema[:fields]

      expect(fields['account'].type).to eq('ManyToOne')
      expect(fields['account'].foreign_key).to eq('account_id')
      expect(fields['account_type'].is_read_only).to be(false)
    end

    it 'keeps the reverse has_many intact instead of filtering it by a phantom type' do
      comments = build_datasource.get_collection('Account').schema[:fields]['payments']

      expect(comments.type).to eq('OneToMany')
      expect(comments.origin_key).to eq('account_id')
    end
  end

  describe 'schema and mapping edge cases' do
    it 'resolves a foreign key that references a non-id primary key' do
      stub_schema(
        [
          {
            'name' => 'transfers', 'kind' => 'OBJECT',
            'fields' => [
              field('id', non_null(scalar('bigint'))),
              field('beneficiary_reference', scalar('String')),
              field('beneficiary', object('beneficiaries'))
            ]
          },
          {
            'name' => 'beneficiaries', 'kind' => 'OBJECT',
            'fields' => [field('reference', non_null(scalar('String'))), field('name', scalar('String'))]
          }
        ],
        [
          list_query('transfers'), by_pk_query('transfers'),
          list_query('beneficiaries'), by_pk_query('beneficiaries', ['reference'])
        ]
      )
      stub_metadata(
        [{ 'table' => { 'schema' => 'public', 'name' => 'transfers' },
           'object_relationships' => [fk_object_rel('beneficiary', 'beneficiary_reference')] }]
      )

      field = build_datasource.get_collection('Transfer').schema[:fields]['beneficiary']

      expect(field.foreign_key).to eq('beneficiary_reference')
      expect(field.foreign_key_target).to eq('reference')
    end

    it 'skips a relationship whose column mapping spans several columns' do
      stub_schema(
        [
          {
            'name' => 'transfers', 'kind' => 'OBJECT',
            'fields' => [
              field('id', non_null(scalar('bigint'))),
              field('tenant_id', non_null(scalar('bigint'))),
              field('account_id', non_null(scalar('bigint'))),
              field('account', object('accounts'))
            ]
          },
          { 'name' => 'accounts', 'kind' => 'OBJECT', 'fields' => [field('id', non_null(scalar('bigint')))] }
        ],
        [list_query('transfers'), by_pk_query('transfers'), list_query('accounts'), by_pk_query('accounts')]
      )
      stub_metadata(
        [{ 'table' => { 'schema' => 'public', 'name' => 'transfers' },
           'object_relationships' => [
             manual_object_rel('account', 'accounts', { 'tenant_id' => 'tenant_id', 'account_id' => 'id' })
           ] }]
      )

      expect(build_datasource.get_collection('Transfer').schema[:fields]).not_to have_key('account')
    end

    it 'skips a table with no detectable primary key instead of exposing a broken collection' do
      stub_schema(
        [{ 'name' => 'transfer_stats', 'kind' => 'OBJECT',
           'fields' => [field('transfer_id', scalar('bigint')), field('total', scalar('bigint'))] }],
        [list_query('transfer_stats')]
      )
      stub_metadata([])

      expect(build_datasource.collections).to be_empty
    end

    it 'ignores relationship metadata of a table name tracked in several schemas' do
      stub_schema(
        [
          {
            'name' => 'transfers', 'kind' => 'OBJECT',
            'fields' => [field('id', non_null(scalar('bigint'))), field('account', object('accounts'))]
          },
          { 'name' => 'accounts', 'kind' => 'OBJECT', 'fields' => [field('id', non_null(scalar('bigint')))] }
        ],
        [list_query('transfers'), by_pk_query('transfers'), list_query('accounts'), by_pk_query('accounts')]
      )
      stub_metadata(
        [
          { 'table' => { 'schema' => 'public', 'name' => 'transfers' },
            'object_relationships' => [fk_object_rel('account', 'account_id')] },
          { 'table' => { 'schema' => 'banking', 'name' => 'transfers' },
            'object_relationships' => [fk_object_rel('account', 'other_account_id')] }
        ]
      )

      # Falls back to the naming convention, which finds no `account_id` column.
      expect(build_datasource.get_collection('Transfer').schema[:fields]).not_to have_key('account')
    end
  end

  describe 'operators advertised per column type' do
    before do
      stub_schema(
        [
          {
            'name' => 'cards', 'kind' => 'OBJECT',
            'fields' => [
              field('id', non_null(scalar('bigint'))),
              field('status', non_null(enum('card_status'))),
              field('tags', scalar('_text')),
              field('label', scalar('String'))
            ]
          },
          { 'name' => 'card_status', 'kind' => 'ENUM', 'enumValues' => [{ 'name' => 'active' }] }
        ],
        [list_query('cards'), by_pk_query('cards')]
      )
      stub_metadata([])
    end

    let(:fields) { build_datasource.get_collection('Card').schema[:fields] }

    # Hasura enum comparison expressions have no _like/_ilike.
    it 'does not advertise pattern operators on enum columns' do
      expect(fields['status'].filter_operators).to include('equal', 'in')
      expect(fields['status'].filter_operators).not_to include('contains', 'i_contains', 'like')
    end

    it 'advertises only translatable operators on array columns' do
      expect(fields['tags'].filter_operators).not_to include('includes_all', 'contains')
      expect(fields['tags'].column_type).to eq(['String'])
    end

    it 'lets the toolkit emulate Present on text columns' do
      expect(fields['label'].filter_operators).to include('not_in')
      expect(fields['label'].filter_operators).not_to include('present')
    end

    it 'marks columns as non-groupable except the foreign keys grouping supports' do
      expect(fields['status'].is_groupable).to be(false)
      expect(fields['label'].is_groupable).to be(false)
    end
  end

  describe 'groupable foreign keys' do
    it 'marks a ManyToOne foreign key as groupable' do
      datasource = BankingSchema.build_datasource
      fields = datasource.get_collection('Comment').schema[:fields]

      expect(fields['membership_id'].is_groupable).to be(true)
      expect(fields['body'].is_groupable).to be(false)
    end
  end
end
