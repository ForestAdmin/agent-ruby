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

    # Hasura only generates `_by_pk` for a real primary key, so an `id` column on a
    # view or a tracked function carries no uniqueness to address records by.
    it 'does not infer a primary key from an id column without a _by_pk query' do
      stub_schema(
        [{ 'name' => 'transfer_views', 'kind' => 'OBJECT',
           'fields' => [field('id', scalar('bigint')), field('total', scalar('bigint'))] }],
        [list_query('transfer_views')]
      )
      stub_metadata([])

      expect(build_datasource.collections).to be_empty
    end

    it 'keeps a scalar column whose name ends with _aggregate' do
      stub_schema(
        [{ 'name' => 'transfers', 'kind' => 'OBJECT',
           'fields' => [field('id', non_null(scalar('bigint'))), field('total_aggregate', scalar('bigint'))] }],
        [list_query('transfers'), by_pk_query('transfers')]
      )
      stub_metadata([])

      fields = build_datasource.get_collection('Transfer').schema[:fields]

      expect(fields['total_aggregate'].type).to eq('Column')
    end

    it 'types a Postgres array after its element type' do
      stub_schema(
        [{ 'name' => 'transfers', 'kind' => 'OBJECT',
           'fields' => [field('id', non_null(scalar('bigint'))), field('scores', scalar('_int4'))] }],
        [list_query('transfers'), by_pk_query('transfers')]
      )
      stub_metadata([])

      expect(build_datasource.get_collection('Transfer').schema[:fields]['scores'].column_type).to eq(['Number'])
    end

    it 'lets an explicit allow-list restore a table the built-in prefixes exclude' do
      stub_schema(
        [{ 'name' => 'pg_stat_activity', 'kind' => 'OBJECT',
           'fields' => [field('id', non_null(scalar('bigint')))] }],
        [list_query('pg_stat_activity'), by_pk_query('pg_stat_activity')]
      )
      stub_metadata([])

      datasource = build_datasource(included_tables: ['pg_stat_activity'])

      expect(datasource.collections.keys).to eq(['PgStatActivity'])
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

    # The bare GraphQL field `transfers` can only be `public.transfers`; the
    # `banking.transfers` metadata belongs to the `banking_transfers` field and
    # must not shadow or invalidate the public mapping.
    it 'keeps the public mapping when another schema tracks the same table name' do
      stub_schema(
        [
          {
            'name' => 'transfers', 'kind' => 'OBJECT',
            'fields' => [
              field('id', non_null(scalar('bigint'))),
              field('account_id', non_null(scalar('bigint'))),
              field('account', object('accounts'))
            ]
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

      account = build_datasource.get_collection('Transfer').schema[:fields]['account']

      expect(account.type).to eq('ManyToOne')
      expect(account.foreign_key).to eq('account_id')
    end

    it 'survives malformed metadata entries by falling back to naming conventions' do
      stub_schema(
        [{ 'name' => 'transfers', 'kind' => 'OBJECT', 'fields' => [field('id', non_null(scalar('bigint')))] }],
        [list_query('transfers'), by_pk_query('transfers')]
      )
      stub_metadata(
        [
          'legacy-string-table-form',
          { 'table' => { 'schema' => 'public', 'name' => 'transfers' },
            'object_relationships' => [{ 'name' => 'broken' }] }
        ]
      )

      expect(build_datasource.collections.keys).to eq(['Transfer'])
    end

    it 'raises a named error when introspection returns no usable schema' do
      WebMock.stub_request(:post, BankingSchema::GRAPHQL_URI)
             .with { |request| request.body.include?('IntrospectSchema') }
             .to_return(status: 200, body: JSON.generate({ 'data' => { '__schema' => nil } }),
                        headers: { 'Content-Type' => 'application/json' })
      stub_metadata([])

      expect { build_datasource }
        .to raise_error(ForestAdminDatasourceGraphqlHasura::IntrospectionError, /introspection enabled/)
    end

    it 'lets an explicit exclusion win over the allow-list' do
      stub_schema(
        [
          { 'name' => 'transfers', 'kind' => 'OBJECT', 'fields' => [field('id', non_null(scalar('bigint')))] },
          { 'name' => 'cards', 'kind' => 'OBJECT', 'fields' => [field('id', non_null(scalar('bigint')))] }
        ],
        [list_query('transfers'), by_pk_query('transfers'), list_query('cards'), by_pk_query('cards')]
      )
      stub_metadata([])

      datasource = build_datasource(included_tables: %w[transfers cards], excluded_tables: ['cards'])

      expect(datasource.collections.keys).to eq(['Transfer'])
    end

    it 'keeps one collection and warns when two tables classify to the same name' do
      stub_schema(
        [
          { 'name' => 'user_status', 'kind' => 'OBJECT', 'fields' => [field('id', non_null(scalar('bigint')))] },
          { 'name' => 'user_statuses', 'kind' => 'OBJECT', 'fields' => [field('id', non_null(scalar('bigint')))] }
        ],
        [list_query('user_status'), by_pk_query('user_status'),
         list_query('user_statuses'), by_pk_query('user_statuses')]
      )
      stub_metadata([])

      datasource = build_datasource

      expect(datasource.collections.keys).to eq(['UserStatus'])
      expect(datasource.get_collection('UserStatus').table_name).to eq('user_status')
    end
  end

  describe 'reverse polymorphic relations' do
    before do
      stub_schema(
        [
          {
            'name' => 'comments', 'kind' => 'OBJECT',
            'fields' => [
              field('id', non_null(scalar('bigint'))),
              field('commentable_type', non_null(scalar('String'))),
              field('commentable_id', non_null(scalar('bigint'))),
              field('transfer', object('transfers'))
            ]
          },
          {
            'name' => 'transfers', 'kind' => 'OBJECT',
            'fields' => [
              field('id', non_null(scalar('bigint'))),
              field('external_id', non_null(scalar('bigint'))),
              field('comments', non_null(list_of(non_null(object('comments')))))
            ]
          }
        ],
        [list_query('comments'), by_pk_query('comments'), list_query('transfers'), by_pk_query('transfers')]
      )
    end

    # The array relationship joins `external_id`, while the polymorphic
    # association targets `id`: it is a different relationship, so it must not be
    # replaced by a PolymorphicOneToMany querying by `id`.
    it 'does not absorb an array relationship whose local key is not the targeted primary key' do
      stub_metadata(
        [
          { 'table' => { 'schema' => 'public', 'name' => 'comments' },
            'object_relationships' => [manual_object_rel('transfer', 'transfers', { 'commentable_id' => 'id' })] },
          { 'table' => { 'schema' => 'public', 'name' => 'transfers' },
            'array_relationships' => [
              manual_object_rel('comments', 'comments', { 'external_id' => 'commentable_id' })
            ] }
        ]
      )

      fields = build_datasource.get_collection('Transfer').schema[:fields]

      expect(fields['comments'].type).to eq('OneToMany')
      expect(fields['comments'].origin_key_target).to eq('external_id')
      expect(fields['transfers']).to be_nil
    end

    it 'absorbs the array relationship that does join the targeted primary key' do
      stub_metadata(
        [
          { 'table' => { 'schema' => 'public', 'name' => 'comments' },
            'object_relationships' => [manual_object_rel('transfer', 'transfers', { 'commentable_id' => 'id' })] },
          { 'table' => { 'schema' => 'public', 'name' => 'transfers' },
            'array_relationships' => [manual_object_rel('comments', 'comments', { 'id' => 'commentable_id' })] }
        ]
      )

      field = build_datasource.get_collection('Transfer').schema[:fields]['comments']

      expect(field.type).to eq('PolymorphicOneToMany')
      expect(field.origin_key_target).to eq('id')
    end
  end

  describe 'composite primary keys' do
    # A join table's key is application-assigned: read-only key columns would
    # make the table impossible to create through Forest Admin.
    it 'keeps composite key columns writable and required' do
      stub_schema(
        [{ 'name' => 'card_memberships', 'kind' => 'OBJECT',
           'fields' => [field('card_id', non_null(scalar('bigint'))),
                        field('membership_id', non_null(scalar('bigint')))] }],
        [list_query('card_memberships'), by_pk_query('card_memberships', %w[card_id membership_id])]
      )
      stub_metadata([])

      fields = build_datasource.get_collection('CardMembership').schema[:fields]

      expect(fields['card_id'].is_read_only).to be(false)
      expect(fields['membership_id'].is_read_only).to be(false)
      expect(fields['card_id'].validation)
        .to eq([{ operator: ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators::PRESENT }])
    end
  end

  describe 'customized root fields' do
    def stub_people_schema(select_config: 'people', extra_roots: {})
      stub_schema(
        [
          {
            'name' => 'person_table', 'kind' => 'OBJECT',
            'fields' => [
              field('id', non_null(scalar('bigint'))),
              field('best_friend_ref', scalar('bigint')),
              field('best_friend', object('person_table'))
            ]
          }
        ],
        [
          field('people', non_null(list_of(non_null(object('person_table'))))),
          { 'name' => 'person_table_by_pk', 'type' => object('person_table'),
            'args' => [{ 'name' => 'id', 'type' => non_null(scalar('bigint')) }] }
        ]
      )
      stub_metadata(
        [
          { 'table' => { 'schema' => 'public', 'name' => 'person_table' },
            'configuration' => { 'custom_root_fields' => { 'select' => select_config }.merge(extra_roots) },
            'object_relationships' => [
              manual_object_rel('best_friend', 'person_table', { 'best_friend_ref' => 'id' })
            ] }
        ]
      )
    end

    # The root select field is renamed to `people`, but relationships and the
    # `_by_pk` query keep referencing the `person_table` GraphQL type: metadata
    # and primary keys must follow what the schema actually exposes.
    it 'applies the metadata and detects the primary key through the GraphQL type' do
      stub_people_schema

      # The Rails class name follows the underlying type (person_table), not
      # the renamed root field (people).
      fields = build_datasource.get_collection('PersonTable').schema[:fields]

      expect(fields['id'].is_primary_key).to be(true)
      expect(fields['best_friend'].type).to eq('ManyToOne')
      expect(fields['best_friend'].foreign_key).to eq('best_friend_ref')
      expect(fields['best_friend'].foreign_collection).to eq('PersonTable')
    end

    it 'accepts the object form of custom_root_fields.select' do
      stub_people_schema(select_config: { 'name' => 'people', 'comment' => 'renamed' })

      field = build_datasource.get_collection('PersonTable').schema[:fields]['best_friend']

      expect(field.foreign_key).to eq('best_friend_ref')
    end

    # Only the select root field is renamed: every other generated name —
    # `<base>_bool_exp`, `insert_<base>`, `<base>_aggregate` — still derives
    # from the type.
    it 'derives type names and mutation roots from the type, the list root from the field' do
      stub_people_schema
      collection = build_datasource.get_collection('PersonTable')

      BankingSchema.stub_graphql_data(
        { 'people' => [] },
        { 'insert_person_table' => { 'returning' => [{ 'id' => 1 }] } }
      )

      toolkit = ForestAdminDatasourceToolkit::Components::Query
      condition = toolkit::ConditionTree::Nodes::ConditionTreeLeaf.new('id', 'equal', 1)
      collection.list(nil, toolkit::Filter.new(condition_tree: condition), toolkit::Projection.new(['id']))
      record = collection.create(nil, { 'best_friend_ref' => 1 })

      expect(record).to eq({ 'id' => 1 })
      queries = []
      expect(WebMock).to(have_requested(:post, BankingSchema::GRAPHQL_URI).at_least_once.with do |req|
        queries << JSON.parse(req.body)['query'] unless req.body.include?('IntrospectSchema')
        true
      end)
      expect(queries[0]).to include('$where: person_table_bool_exp')
      expect(queries[0]).to include('people(where: $where)')
      expect(queries[1]).to include('insert_person_table(objects: $objects)')
    end

    it 'follows renamed mutation and aggregate roots from the metadata' do
      stub_people_schema(extra_roots: { 'insert' => 'createPerson', 'select_aggregate' => 'peopleStats' })
      collection = build_datasource.get_collection('PersonTable')
      BankingSchema.stub_graphql_data(
        { 'createPerson' => { 'returning' => [{ 'id' => 1 }] } },
        { 'peopleStats' => { 'aggregate' => { 'count' => 3, 'row_count' => 3 } } }
      )

      toolkit = ForestAdminDatasourceToolkit::Components::Query
      record = collection.create(nil, { 'best_friend_ref' => 1 })
      result = collection.aggregate(nil, toolkit::Filter.new, toolkit::Aggregation.new(operation: 'Count'))

      expect(record).to eq({ 'id' => 1 })
      expect(result).to eq([{ 'value' => 3, 'group' => {} }])
      queries = []
      expect(WebMock).to(have_requested(:post, BankingSchema::GRAPHQL_URI).at_least_once.with do |req|
        queries << JSON.parse(req.body)['query'] unless req.body.include?('IntrospectSchema')
        true
      end)
      expect(queries[0]).to include('createPerson(objects: $objects)')
      expect(queries[1]).to include('peopleStats')
    end

    # A custom-named select_by_pk root returns the bare object: it is a lookup,
    # not a second table, and must not shadow the real collection.
    it 'does not mistake a custom-named by_pk root field for a table' do
      stub_schema(
        [
          { 'name' => 'users', 'kind' => 'OBJECT', 'fields' => [field('id', non_null(scalar('bigint')))] }
        ],
        [
          list_query('users'), by_pk_query('users'),
          { 'name' => 'user', 'type' => object('users'),
            'args' => [{ 'name' => 'id', 'type' => non_null(scalar('bigint')) }] }
        ]
      )
      stub_metadata([])

      datasource = build_datasource

      expect(datasource.collections.keys).to eq(['User'])
      expect(datasource.get_collection('User').table_name).to eq('users')
    end

    # Crossed renames: table A's type name equals table B's root field name.
    # Each collection must still classify from its own underlying type.
    it 'does not let one table type shadow another table root field' do
      stub_schema(
        [
          { 'name' => 'accounts', 'kind' => 'OBJECT', 'fields' => [field('id', non_null(scalar('bigint')))] },
          { 'name' => 'team_accounts', 'kind' => 'OBJECT',
            'fields' => [field('id', non_null(scalar('bigint')))] }
        ],
        [
          field('accounts_list', non_null(list_of(non_null(object('accounts'))))),
          by_pk_query('accounts'),
          field('accounts', non_null(list_of(non_null(object('team_accounts'))))),
          by_pk_query('team_accounts')
        ]
      )
      stub_metadata(
        [
          { 'table' => { 'schema' => 'public', 'name' => 'accounts' },
            'configuration' => { 'custom_root_fields' => { 'select' => 'accounts_list' } } },
          { 'table' => { 'schema' => 'public', 'name' => 'team_accounts' },
            'configuration' => { 'custom_root_fields' => { 'select' => 'accounts' } } }
        ]
      )

      datasource = build_datasource

      expect(datasource.collections.keys.sort).to eq(%w[Account TeamAccount])
      expect(datasource.get_collection('TeamAccount').table_name).to eq('accounts')
      expect(datasource.get_collection('Account').table_name).to eq('accounts_list')
    end

    # The graphql-default naming convention camelizes root and relationship
    # fields; the metadata keying must match either spelling, and ByPk-suffixed
    # roots still drive primary key detection.
    it 'matches camelized root and relationship fields' do
      stub_schema(
        [
          {
            'name' => 'userAddresses', 'kind' => 'OBJECT',
            'fields' => [
              field('id', non_null(scalar('bigint'))),
              field('ownerRef', scalar('bigint')),
              field('bestFriend', object('userAddresses'))
            ]
          }
        ],
        [
          field('userAddresses', non_null(list_of(non_null(object('userAddresses'))))),
          { 'name' => 'userAddressesByPk', 'type' => object('userAddresses'),
            'args' => [{ 'name' => 'id', 'type' => non_null(scalar('bigint')) }] }
        ]
      )
      stub_metadata(
        [
          { 'table' => { 'schema' => 'public', 'name' => 'user_addresses' },
            'configuration' => { 'custom_root_fields' => { 'select' => 'userAddresses' } },
            'object_relationships' => [
              manual_object_rel('best_friend', 'user_addresses', { 'owner_ref' => 'id' })
            ] }
        ]
      )

      fields = build_datasource.get_collection('UserAddress').schema[:fields]

      expect(fields['id'].is_primary_key).to be(true)
      expect(fields['bestFriend'].type).to eq('ManyToOne')
      # The mapping columns are translated along with the key.
      expect(fields['bestFriend'].foreign_key).to eq('ownerRef')
    end
  end

  describe 'a polymorphic association inside a composite primary key' do
    # Rails taggings: (tag_id, taggable_id, taggable_type) composite key with a
    # polymorphic taggable. Locking the discriminators read-only would make the
    # table impossible to create through.
    it 'keeps the discriminator key members writable' do
      stub_schema(
        [
          {
            'name' => 'taggings', 'kind' => 'OBJECT',
            'fields' => [
              field('tag_id', non_null(scalar('bigint'))),
              field('taggable_type', non_null(scalar('String'))),
              field('taggable_id', non_null(scalar('bigint'))),
              field('transfer', object('transfers'))
            ]
          },
          { 'name' => 'transfers', 'kind' => 'OBJECT', 'fields' => [field('id', non_null(scalar('bigint')))] }
        ],
        [list_query('taggings'), by_pk_query('taggings', %w[tag_id taggable_id taggable_type]),
         list_query('transfers'), by_pk_query('transfers')]
      )
      stub_metadata(
        [{ 'table' => { 'schema' => 'public', 'name' => 'taggings' },
           'object_relationships' => [manual_object_rel('transfer', 'transfers', { 'taggable_id' => 'id' })] }]
      )

      fields = build_datasource.get_collection('Tagging').schema[:fields]

      expect(fields['taggable'].type).to eq('PolymorphicManyToOne')
      expect(fields['taggable_id'].is_read_only).to be(false)
      expect(fields['taggable_type'].is_read_only).to be(false)
    end

    it 'locks non-key discriminators and clears their validation' do
      fields = BankingSchema.build_datasource.get_collection('Comment').schema[:fields]

      expect(fields['commentable_id'].is_read_only).to be(true)
      # A read-only field must not demand a value the user cannot type in.
      expect(fields['commentable_id'].validation).to eq([])
      expect(fields['commentable_type'].validation).to eq([])
    end
  end

  describe 'money columns' do
    # Hasura serializes money in its Postgres text form ("$1,100.00"): as a
    # Number it would aggregate to silently wrong charts.
    it 'surfaces money as text' do
      stub_schema(
        [{ 'name' => 'invoices', 'kind' => 'OBJECT',
           'fields' => [field('id', non_null(scalar('bigint'))), field('total', scalar('money'))] }],
        [list_query('invoices'), by_pk_query('invoices')]
      )
      stub_metadata([])

      expect(build_datasource.get_collection('Invoice').schema[:fields]['total'].column_type).to eq('String')
    end
  end

  describe 'configured polymorphism without the Hasura metadata' do
    # With every mapping unknown, two relationships towards the same configured
    # target are indistinguishable — one may be a plain belongs_to whose
    # absorption would silently delete it.
    it 'refuses to guess between two relationships towards the same target' do
      stub_schema(
        [
          {
            'name' => 'comments', 'kind' => 'OBJECT',
            'fields' => [
              field('id', non_null(scalar('bigint'))),
              field('commentable_type', non_null(scalar('String'))),
              field('commentable_id', non_null(scalar('bigint'))),
              field('transfer', object('transfers')),
              field('reviewed_transfer', object('transfers'))
            ]
          },
          { 'name' => 'transfers', 'kind' => 'OBJECT', 'fields' => [field('id', non_null(scalar('bigint')))] }
        ],
        [list_query('comments'), by_pk_query('comments'), list_query('transfers'), by_pk_query('transfers')]
      )
      WebMock.stub_request(:post, BankingSchema::METADATA_URI).to_return(status: 403, body: '{}')

      datasource = build_datasource(
        polymorphic_relations: { 'comments' => { 'commentable' => %w[transfers] } }
      )

      expect(datasource.get_collection('Comment').schema[:fields]).not_to have_key('commentable')
    end
  end

  describe 'a column literally named _type' do
    it 'does not detect an unnamed polymorphic base and keeps the relationship' do
      stub_schema(
        [
          {
            'name' => 'events', 'kind' => 'OBJECT',
            'fields' => [
              field('id', non_null(scalar('bigint'))),
              field('_type', scalar('String')),
              field('_id', scalar('bigint')),
              field('owner', object('owners'))
            ]
          },
          { 'name' => 'owners', 'kind' => 'OBJECT', 'fields' => [field('id', non_null(scalar('bigint')))] }
        ],
        [list_query('events'), by_pk_query('events'), list_query('owners'), by_pk_query('owners')]
      )
      stub_metadata(
        [{ 'table' => { 'schema' => 'public', 'name' => 'events' },
           'object_relationships' => [manual_object_rel('owner', 'owners', { '_id' => 'id' })] }]
      )

      fields = build_datasource.get_collection('Event').schema[:fields]

      expect(fields).not_to have_key('')
      expect(fields['owner'].type).to eq('ManyToOne')
    end
  end

  describe 'a column named like the polymorphic association' do
    it 'keeps the physical column and skips the association' do
      stub_schema(
        [
          {
            'name' => 'comments', 'kind' => 'OBJECT',
            'fields' => [
              field('id', non_null(scalar('bigint'))),
              field('commentable', scalar('String')),
              field('commentable_type', non_null(scalar('String'))),
              field('commentable_id', non_null(scalar('bigint'))),
              field('transfer', object('transfers'))
            ]
          },
          { 'name' => 'transfers', 'kind' => 'OBJECT', 'fields' => [field('id', non_null(scalar('bigint')))] }
        ],
        [list_query('comments'), by_pk_query('comments'), list_query('transfers'), by_pk_query('transfers')]
      )
      stub_metadata(
        [{ 'table' => { 'schema' => 'public', 'name' => 'comments' },
           'object_relationships' => [manual_object_rel('transfer', 'transfers', { 'commentable_id' => 'id' })] }]
      )

      fields = build_datasource.get_collection('Comment').schema[:fields]

      expect(fields['commentable'].type).to eq('Column')
      expect(fields['commentable_type'].is_read_only).to be(false)
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
    it 'marks a ManyToOne foreign key as groupable when its reverse relationship is declared' do
      datasource = BankingSchema.build_datasource
      fields = datasource.get_collection('Comment').schema[:fields]

      expect(fields['membership_id'].is_groupable).to be(true)
      expect(fields['body'].is_groupable).to be(false)
    end

    # Grouping goes through the parent's nested `<relation>_aggregate`, which only
    # exists when Hasura declares the reverse array relationship: advertising the
    # foreign key would offer a group-by that the aggregator then rejects.
    it 'does not mark a foreign key groupable when no reverse relationship is declared' do
      stub_schema(
        [
          {
            'name' => 'payments', 'kind' => 'OBJECT',
            'fields' => [
              field('id', non_null(scalar('bigint'))),
              field('account_id', non_null(scalar('bigint'))),
              field('account', object('accounts'))
            ]
          },
          { 'name' => 'accounts', 'kind' => 'OBJECT', 'fields' => [field('id', non_null(scalar('bigint')))] }
        ],
        [list_query('payments'), by_pk_query('payments'), list_query('accounts'), by_pk_query('accounts')]
      )
      stub_metadata(
        [{ 'table' => { 'schema' => 'public', 'name' => 'payments' },
           'object_relationships' => [fk_object_rel('account', 'account_id')] }]
      )

      fields = build_datasource.get_collection('Payment').schema[:fields]

      expect(fields['account'].type).to eq('ManyToOne')
      expect(fields['account_id'].is_groupable).to be(false)
    end
  end
end
