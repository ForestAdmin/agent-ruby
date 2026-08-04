# End-to-end validation against a real Hasura instance (see docker-compose.yml).
#
#   docker compose -f validation/docker-compose.yml up -d
#   bash validation/setup_hasura.sh
#   BUNDLE_GEMFILE=Gemfile-test bundle exec ruby validation/validate.rb
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'forest_admin_datasource_toolkit'
require 'forest_admin_datasource_customizer'
require 'forest_admin_datasource_graphql_hasura'

URI_GRAPHQL = ENV.fetch('HASURA_URL', 'http://localhost:58080/v1/graphql')
HEADERS = { 'x-hasura-admin-secret' => ENV.fetch('ADMIN_SECRET', 'hasura-validation-secret') }.freeze

Query = ForestAdminDatasourceToolkit::Components::Query
Nodes = Query::ConditionTree::Nodes
Operators = Query::ConditionTree::Operators

RESULTS = [] # rubocop:disable Style/MutableConstant -- scenario accumulator

def scenario(name)
  yield
  RESULTS << [name, :pass, nil]
  puts "  \e[32mPASS\e[0m #{name}"
rescue StandardError => e
  RESULTS << [name, :fail, e]
  puts "  \e[31mFAIL\e[0m #{name}\n       #{e.class}: #{e.message.lines.first&.strip}"
end

def assert(condition, message)
  raise "assertion failed: #{message}" unless condition
end

def assert_equal(expected, actual, message)
  raise "#{message}\n  expected: #{expected.inspect}\n  actual:   #{actual.inspect}" unless expected == actual
end

def projection(*fields) = Query::Projection.new(fields)
def filter(**options) = Query::Filter.new(**options)
def leaf(field, operator, value = nil) = Nodes::ConditionTreeLeaf.new(field, operator, value)
def branch(aggregator, conditions) = Nodes::ConditionTreeBranch.new(aggregator, conditions)

puts "\n== Introspection (metadata API available) =="

datasource = ForestAdminDatasourceGraphqlHasura::Datasource.new(
  uri: URI_GRAPHQL,
  headers: HEADERS,
  type_values: { 'bank_accounts' => 'Banking::BankAccount' }
)

scenario 'collections are registered under Rails class names' do
  expected = %w[Attachment Banking__BankAccount Card CardMembership Comment Membership Transfer]
  assert_equal expected, datasource.collections.keys.sort, 'collection names'
end

scenario 'comments.commentable is a PolymorphicManyToOne (Transfer | Card)' do
  field = datasource.get_collection('Comment').schema[:fields]['commentable']
  assert_equal 'PolymorphicManyToOne', field.type, 'relation type'
  assert_equal %w[Card Transfer], field.foreign_collections.sort, 'targets'
  assert_equal({ 'Transfer' => 'id', 'Card' => 'id' }, field.foreign_key_targets, 'targets pks')
  fields = datasource.get_collection('Comment').schema[:fields]
  assert !fields.key?('transfer') && !fields.key?('card'), 'per-target relations must be absorbed'
end

scenario 'attachments has two polymorphic belongs_to (attachable multi-target namespaced, author single-target)' do
  fields = datasource.get_collection('Attachment').schema[:fields]
  assert_equal 'PolymorphicManyToOne', fields['attachable'].type, 'attachable type'
  assert_equal %w[Banking__BankAccount Transfer], fields['attachable'].foreign_collections.sort, 'attachable targets'
  assert_equal 'PolymorphicManyToOne', fields['author'].type, 'author type'
  assert_equal %w[Membership], fields['author'].foreign_collections, 'author targets'
end

scenario 'uuid and composite primary keys are detected' do
  attachment_fields = datasource.get_collection('Attachment').schema[:fields]
  assert_equal 'Uuid', attachment_fields['id'].column_type, 'attachments.id type'
  assert attachment_fields['id'].is_primary_key, 'attachments.id must be pk'

  join_fields = datasource.get_collection('CardMembership').schema[:fields]
  assert join_fields['card_id'].is_primary_key && join_fields['membership_id'].is_primary_key,
         'card_memberships composite pk'
end

scenario 'reverse PolymorphicOneToMany are emitted with the raw stored type value' do
  transfers = datasource.get_collection('Transfer').schema[:fields]
  assert_equal 'PolymorphicOneToMany', transfers['comments'].type, 'Transfer.comments'
  assert_equal 'Transfer', transfers['comments'].origin_type_value, 'Transfer.comments type value'
  assert_equal 'PolymorphicOneToMany', transfers['attachments'].type, 'Transfer.attachments'

  bank_accounts = datasource.get_collection('Banking__BankAccount').schema[:fields]
  assert_equal 'Banking::BankAccount', bank_accounts['attachments'].origin_type_value,
               'namespaced raw type value'

  memberships = datasource.get_collection('Membership').schema[:fields]
  assert_equal 'PolymorphicOneToMany', memberships['attachments'].type, 'Membership.attachments (author)'
  assert_equal 'OneToMany', memberships['comments'].type, 'Membership.comments stays a plain OneToMany'
end

scenario 'toolkit pairs both sides (inverseOf)' do
  inverse = ForestAdminDatasourceToolkit::Utils::Collection.get_inverse_relation(
    datasource.get_collection('Transfer'), 'comments'
  )
  assert_equal 'commentable', inverse, 'inverse relation'
end

puts "\n== Runtime: list =="

comments = datasource.get_collection('Comment')

scenario 'list with commentable:* returns phantom records built from the discriminator columns' do
  records = comments.list(nil, filter, projection('id', 'body', 'commentable_type', 'commentable:*'))
  by_body = records.to_h { |record| [record['body'], record] }

  assert_equal({ '*' => nil }, by_body['on transfer 1']['commentable'], 'phantom for transfer comment')
  assert_equal 1, by_body['on transfer 1']['commentable_id'], 'fk selected even if not projected'
  assert_equal({ '*' => nil }, by_body['dangling target']['commentable'], 'dangling id still yields a phantom')
  assert by_body['no target']['commentable'].nil?, 'null reference yields nil'
end

scenario 'the faux-join trap is dead: related data of Transfer#1 excludes Card#1 comments' do
  condition = branch('And', [
                       leaf('commentable_id', Operators::EQUAL, 1),
                       leaf('commentable_type', Operators::EQUAL, 'Transfer')
                     ])
  records = comments.list(nil, filter(condition_tree: condition), projection('id', 'body'))

  assert_equal ['on transfer 1', 'second on transfer 1'], records.map { |r| r['body'] }.sort, 'transfer comments'
end

scenario 'regular ManyToOne joins through Hasura' do
  records = comments.list(
    nil,
    filter(condition_tree: leaf('body', Operators::EQUAL, 'on card 1')),
    projection('id', 'membership:full_name')
  )
  assert_equal 'Jane Doe', records.first&.dig('membership', 'full_name'), 'joined membership'
end

scenario 'sort, pagination and operators' do
  records = comments.list(
    nil,
    filter(
      condition_tree: leaf('body', Operators::I_CONTAINS, 'transfer'),
      sort: Query::Sort.new([{ field: 'id', ascending: false }]),
      page: Query::Page.new(offset: 0, limit: 1)
    ),
    projection('id', 'body')
  )
  assert_equal ['second on transfer 1'], records.map { |r| r['body'] }, 'filtered+sorted+paged'
end

scenario 'uuid-pk collection lists with its polymorphic relations' do
  attachments = datasource.get_collection('Attachment')
  records = attachments.list(nil, filter, projection('id', 'file_name', 'attachable:*', 'author:*'))
  rib = records.find { |r| r['file_name'] == 'rib.pdf' }

  assert_equal 'Banking::BankAccount', rib['attachable_type'], 'namespaced raw type in record'
  assert_equal({ '*' => nil }, rib['attachable'], 'attachable phantom')
  assert_equal({ '*' => nil }, rib['author'], 'author phantom')
end

puts "\n== Runtime: writes =="

created_id = nil

scenario 'create / update / delete a comment' do
  record = comments.create(nil, {
                             'body' => 'validation temp',
                             'commentable_type' => 'Transfer',
                             'commentable_id' => 2,
                             'membership_id' => 1
                           })
  created_id = record['id']
  assert created_id, 'created id returned'

  comments.update(nil, filter(condition_tree: leaf('id', Operators::EQUAL, created_id)), { 'body' => 'edited' })
  after = comments.list(nil, filter(condition_tree: leaf('id', Operators::EQUAL, created_id)),
                        projection('id', 'body'))
  assert_equal 'edited', after.first&.fetch('body'), 'update applied'

  comments.delete(nil, filter(condition_tree: leaf('id', Operators::EQUAL, created_id)))
  gone = comments.list(nil, filter(condition_tree: leaf('id', Operators::EQUAL, created_id)), projection('id'))
  assert gone.empty?, 'record deleted'
end

puts "\n== Runtime: aggregates =="

scenario 'simple count with filter' do
  aggregation = Query::Aggregation.new(operation: 'Count')
  condition = leaf('commentable_type', Operators::EQUAL, 'Transfer')
  result = comments.aggregate(nil, filter(condition_tree: condition), aggregation)
  assert_equal 7, result.first&.fetch('value'), 'transfer-typed comments count'
end

scenario 'count grouped by foreign key (chart use case)' do
  aggregation = Query::Aggregation.new(operation: 'Count', groups: [{ field: 'membership_id' }])
  result = comments.aggregate(nil, filter, aggregation)
  grouped = result.to_h { |row| [row['group']['membership_id'], row['value']] }
  assert_equal({ 1 => 8, 2 => 2 }, grouped, 'counts per membership')
end

puts "\n== Config modes =="

scenario 'metadata API blocked: polymorphic_relations configuration takes over' do
  blocked = ForestAdminDatasourceGraphqlHasura::Datasource.new(
    uri: URI_GRAPHQL,
    headers: HEADERS,
    metadata_uri: 'http://localhost:58080/v1/metadata-blocked',
    type_values: { 'bank_accounts' => 'Banking::BankAccount' },
    polymorphic_relations: {
      'comments' => { 'commentable' => %w[transfers cards] },
      'attachments' => { 'attachable' => %w[transfers bank_accounts], 'author' => %w[memberships] }
    }
  )

  commentable = blocked.get_collection('Comment').schema[:fields]['commentable']
  assert_equal 'PolymorphicManyToOne', commentable.type, 'commentable via config'
  assert_equal %w[Card Transfer], commentable.foreign_collections.sort, 'targets via config'

  records = blocked.get_collection('Comment').list(nil, filter, projection('id', 'body', 'commentable:*'))
  assert records.any? { |r| r['commentable'] == { '*' => nil } }, 'phantoms still materialized'
end

scenario 'STI legacy rows: subclass name stored in the type column is surfaced as-is' do
  records = comments.list(
    nil,
    filter(condition_tree: leaf('body', Operators::EQUAL, 'legacy sti row')),
    projection('id', 'body', 'commentable_type', 'commentable:*')
  )
  # Rails stores base_class.name since 6.1, so only legacy rows hold a subclass
  # name — which matches no collection and stays unresolved.
  assert_equal 'FlashCard', records.first&.fetch('commentable_type'), 'raw legacy value kept'
end

puts "\n== Adversarial-review regressions =="

scenario 'a real FK next to a <base>_type enum stays a plain ManyToOne' do
  fields = datasource.get_collection('Transfer').schema[:fields]

  assert_equal 'ManyToOne', fields['beneficiary'].type, 'beneficiary relation type'
  assert_equal 'beneficiary_id', fields['beneficiary'].foreign_key, 'beneficiary fk'
  assert_equal false, fields['beneficiary_type'].is_read_only, 'business enum stays writable'
  assert_equal 'OneToMany', datasource.get_collection('Membership').schema[:fields]['transfers'].type,
               'reverse has_many stays a plain OneToMany'
end

scenario 'the reverse has_many of that FK returns rows (not filtered by a phantom type)' do
  transfers = datasource.get_collection('Transfer')
  records = transfers.list(nil, filter(condition_tree: leaf('beneficiary_id', Operators::EQUAL, 1)),
                           projection('id', 'amount_cents'))

  assert_equal 1, records.size, 'transfers of membership 1'
end

scenario 'a view without a primary key is not exposed' do
  assert !datasource.collections.key?('TransferStat'), 'PK-less view must be skipped'
end

scenario 'enum columns do not advertise pattern operators, array columns stay filterable-safe' do
  card_fields = datasource.get_collection('Card').schema[:fields]
  transfer_fields = datasource.get_collection('Transfer').schema[:fields]

  assert !card_fields['status'].filter_operators.include?('i_contains'), 'no ilike on a PG enum'
  assert !transfer_fields['tags'].filter_operators.include?('includes_all'), 'no unsupported array operator'
  assert_equal ['String'], transfer_fields['tags'].column_type, 'PG array detected'
end

scenario 'Sum over zero rows returns a row (charts read result[0])' do
  transfers = datasource.get_collection('Transfer')
  aggregation = Query::Aggregation.new(operation: 'Sum', field: 'amount_cents')
  result = transfers.aggregate(nil, filter(condition_tree: leaf('id', Operators::EQUAL, 99_999)), aggregation)

  assert_equal 1, result.size, 'exactly one row'
  assert result.first['value'].nil?, 'null value, which the charts route turns into 0'
end

scenario 'an aggregation field that is not a column is rejected, not interpolated' do
  hostile = 'amount_cents } } } cards { id } dummy: transfers_aggregate { aggregate { sum { amount_cents'
  aggregation = Query::Aggregation.new(operation: 'Sum', field: hostile)

  begin
    datasource.get_collection('Transfer').aggregate(nil, filter, aggregation)
    raise 'expected the hostile aggregation field to be rejected'
  rescue ForestAdminDatasourceToolkit::Exceptions::ForestException => e
    assert e.message.match?(/not found|Invalid aggregation field/), "unexpected message: #{e.message}"
  end
end

scenario 'leaderboard grouping through a relation path works' do
  aggregation = Query::Aggregation.new(operation: 'Count', groups: [{ field: 'membership:full_name' }])
  result = comments.aggregate(nil, filter, aggregation)
  grouped = result.to_h { |row| [row['group']['membership:full_name'], row['value']] }

  assert_equal({ 'Jane Doe' => 8, 'John Smith' => 2 }, grouped, 'counts per membership name')
end

scenario 'Sum grouped by FK handles bigint values returned as JSON strings' do
  transfers = datasource.get_collection('Transfer')
  aggregation = Query::Aggregation.new(operation: 'Sum', field: 'amount_cents',
                                       groups: [{ field: 'beneficiary_id' }])
  result = transfers.aggregate(nil, filter, aggregation)

  assert_equal 2, result.size, 'one row per beneficiary'
  # Highest first, whatever the wire type of the bigint.
  assert_equal 1, result.first['group']['beneficiary_id'], 'sorted by value desc'
end

# The operator-equivalence decorator always sits above a datasource in a running
# agent; only it is instantiated here, as the full stack pulls in the agent gem.
scenario 'Present and Blank do not overlap on a text column (through operator equivalence)' do
  decorated = ForestAdminDatasourceCustomizer::Decorators::OperatorsEquivalence::
    OperatorsEquivalenceCollectionDecorator.new(comments, datasource)

  agent_caller = ForestAdminDatasourceToolkit::Components::Caller.new(
    id: 1, email: 'validation@forestadmin.com', first_name: 'V', last_name: 'A', team: 'ops',
    rendering_id: 1, tags: {}, timezone: 'Europe/Paris', permission_level: 'admin'
  )

  present = decorated.list(agent_caller, filter(condition_tree: leaf('body', Operators::PRESENT)),
                           projection('id', 'body'))
  blank = decorated.list(agent_caller, filter(condition_tree: leaf('body', Operators::BLANK)),
                         projection('id', 'body'))

  assert present.none? { |r| r['body'].nil? || r['body'].empty? }, 'present excludes NULL and empty string'
  assert blank.any? { |r| r['body'].nil? }, 'blank includes NULL rows'
  assert blank.any? { |r| r['body'] == '' }, 'blank includes empty strings'
  assert (present.map { |r| r['id'] } & blank.map { |r| r['id'] }).empty?, 'no overlap'
end

scenario 'Contains searches a literal % instead of treating it as a wildcard' do
  records = comments.list(nil, filter(condition_tree: leaf('body', Operators::CONTAINS, 'discount 100%')),
                          projection('id', 'body'))

  assert_equal ['discount 100% applied'], records.map { |r| r['body'] }, 'only the literal match'
end

scenario 'Contains is case-insensitive, like the other datasources' do
  records = comments.list(nil, filter(condition_tree: leaf('body', Operators::CONTAINS, 'ON TRANSFER')),
                          projection('id', 'body'))

  assert records.size >= 2, "expected case-insensitive matches, got #{records.size}"
end

scenario 'a jsonb column survives create and update' do
  record = comments.create(nil, {
                             'body' => 'jsonb probe',
                             'metadata' => { 'source' => 'validation', 'nested' => { 'ok' => true } },
                             'commentable_type' => 'Transfer',
                             'commentable_id' => 1
                           })
  probe_id = record['id']

  comments.update(nil, filter(condition_tree: leaf('id', Operators::EQUAL, probe_id)),
                  { 'metadata' => { 'source' => 'edited' } })
  after = comments.list(nil, filter(condition_tree: leaf('id', Operators::EQUAL, probe_id)),
                        projection('id', 'metadata'))

  assert_equal({ 'source' => 'edited' }, after.first&.fetch('metadata'), 'jsonb patch applied')
ensure
  comments.delete(nil, filter(condition_tree: leaf('id', Operators::EQUAL, probe_id))) if probe_id
end

scenario 'an explicit nil is persisted as null rather than falling back to the column default' do
  cards = datasource.get_collection('Card')
  record = cards.create(nil, { 'last4' => nil, 'type' => 'Card' })
  probe_id = record['id']

  assert record['last4'].nil?, 'last4 stored as null'
ensure
  cards.delete(nil, filter(condition_tree: leaf('id', Operators::EQUAL, probe_id))) if probe_id
end

scenario 'an unknown polymorphic type value is left unresolved instead of breaking the page' do
  records = comments.list(nil, filter(condition_tree: leaf('body', Operators::EQUAL, 'legacy sti row')),
                          projection('id', 'body', 'commentable_type', 'commentable:*'))

  assert_equal 'FlashCard', records.first['commentable_type'], 'raw value kept'
  assert records.first['commentable'].nil?, 'no phantom for a type matching no collection'
end

scenario 'update refuses to run without any condition' do
  comments.update(nil, filter, { 'body' => 'mass update' })
  raise 'expected an unfiltered update to be refused'
rescue ForestAdminDatasourceToolkit::Exceptions::ForestException => e
  assert e.message.include?('Refusing'), "unexpected message: #{e.message}"
end

scenario 'a transport failure surfaces as a Forest validation error, not an opaque crash' do
  unreachable = ForestAdminDatasourceGraphqlHasura::Client.new(
    ForestAdminDatasourceGraphqlHasura::Configuration.new(uri: 'http://127.0.0.1:1/v1/graphql', timeout: 2)
  )

  begin
    unreachable.execute('query { __typename }')
    raise 'expected a transport failure'
  rescue ForestAdminDatasourceGraphqlHasura::GraphqlError => e
    assert e.is_a?(ForestAdminDatasourceToolkit::Exceptions::ForestException), 'must be a ForestException'
    assert e.message.include?('Could not reach'), "unexpected message: #{e.message}"
  end
end

failures = RESULTS.count { |(_, status, _)| status == :fail }
puts "\n#{RESULTS.size} scenarios, #{failures} failure(s)"
exit(failures.zero? ? 0 : 1)
