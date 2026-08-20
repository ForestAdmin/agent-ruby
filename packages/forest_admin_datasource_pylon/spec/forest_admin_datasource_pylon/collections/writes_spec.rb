module ForestAdminDatasourcePylon
  RSpec.describe Collections::Writes do
    def filter(condition_tree: nil, search: nil)
      ForestAdminDatasourceToolkit::Components::Query::Filter.new(condition_tree: condition_tree, search: search)
    end

    def leaf(field, operator, value)
      ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf
        .new(field, operator, value)
    end

    def branch(aggregator, conditions)
      ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeBranch
        .new(aggregator, conditions)
    end

    def id_filter(operator, value)
      filter(condition_tree: leaf('id', operator, value))
    end

    def json(payload, status = 200)
      { status: status, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
    end

    def custom_field(type, slug, extra = {})
      { 'id' => "cf_#{slug}", 'slug' => slug, 'label' => slug, 'type' => type,
        'object_type' => 'issue', 'is_read_only' => false }.merge(extra)
    end

    def options(*slugs)
      { 'select_metadata' => { 'options' => slugs.map { |slug| { 'label' => slug.upcase, 'slug' => slug } } } }
    end

    def issue_payload(id, overrides = {})
      { 'id' => id, 'number' => 12, 'title' => 'Boom', 'body_html' => '<p>boom</p>', 'state' => 'new',
        'type' => 'ticket', 'source' => 'manual', 'account' => { 'id' => 'acc-1' }, 'tags' => %w[urgent],
        'custom_fields' => {}, 'created_at' => '2026-08-07T13:06:22Z' }.merge(overrides)
    end

    # A text field, a select read and written by the slug of its option, a
    # multiselect Pylon takes through `values`, and one it syncs from an app and
    # refuses to be written.
    let(:issue_custom_fields) do
      [custom_field('text', 'severity'),
       custom_field('select', 'priority', options('p1', 'p2')),
       custom_field('multiselect', 'regions', options('us', 'emea')),
       custom_field('text', 'synced_id', 'is_read_only' => true)]
    end

    let(:datasource) { Datasource.new(api_key: 'k') }
    let(:base) { datasource.configuration.url }
    let(:issues) { datasource.get_collection('PylonIssue') }
    let(:accounts) { datasource.get_collection('PylonAccount') }
    let(:contacts) { datasource.get_collection('PylonContact') }
    let(:teams) { datasource.get_collection('PylonTeam') }
    let(:users) { datasource.get_collection('PylonUser') }
    let(:operators) { ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators }

    before { stub_custom_fields(issue: issue_custom_fields) }

    describe '#create' do
      it 'posts the writable columns and answers with the serialized record' do
        stub_request(:post, "#{base}/issues").to_return(json('data' => issue_payload('i1')))

        record = issues.create(nil, 'title' => 'Boom', 'body_html' => '<p>boom</p>', 'tags' => %w[urgent],
                                    'account_id' => 'acc-1')

        expect(record).to include('id' => 'i1', 'title' => 'Boom', 'account_id' => 'acc-1')
        expect(WebMock).to have_requested(:post, "#{base}/issues")
          .with(body: { 'title' => 'Boom', 'body_html' => '<p>boom</p>',
                        'tags' => %w[urgent], 'account_id' => 'acc-1' })
      end

      # The schema is the single source of truth for what may be written: a
      # read-only column reaching the payload is the agent's doing, not a request
      # the operator made, so it is dropped rather than refused.
      it 'drops the read-only columns and the keys the schema does not know' do
        stub_request(:post, "#{base}/issues").to_return(json('data' => issue_payload('i1')))

        issues.create(nil, 'title' => 'Boom', 'id' => 'i9', 'number' => 3, 'link' => 'http://x',
                           'created_at' => '2026-01-01', 'source' => 'manual', 'messages' => [],
                           'number_of_touches' => 4, 'not_a_column' => 'x')

        expect(WebMock).to have_requested(:post, "#{base}/issues").with(body: { 'title' => 'Boom' })
      end

      # Pylon fills in what a create leaves out, so a form field the operator
      # never touched travels as nothing at all rather than as an explicit null.
      it 'drops the columns left empty' do
        stub_request(:post, "#{base}/issues").to_return(json('data' => issue_payload('i1')))

        issues.create(nil, 'title' => 'Boom', 'team_id' => nil, 'tags' => nil)

        expect(WebMock).to have_requested(:post, "#{base}/issues").with(body: { 'title' => 'Boom' })
      end
    end

    describe '#create with custom fields' do
      it 'writes them as a list, through `value` or `values`, and leaves the synced one out' do
        stub_request(:post, "#{base}/issues").to_return(json('data' => issue_payload('i1')))

        issues.create(nil, 'title' => 'Boom', 'severity' => 'high', 'priority' => 'p2',
                           'regions' => %w[us emea], 'synced_id' => 'zzz')

        expect(WebMock).to have_requested(:post, "#{base}/issues").with(
          body: { 'title' => 'Boom',
                  'custom_fields' => [{ 'slug' => 'severity', 'value' => 'high' },
                                      { 'slug' => 'priority', 'value' => 'p2' },
                                      { 'slug' => 'regions', 'values' => %w[us emea] }] }
        )
      end

      it 'sends no custom_fields key when none was set' do
        stub_request(:post, "#{base}/issues").to_return(json('data' => issue_payload('i1')))

        issues.create(nil, 'title' => 'Boom')

        expect(WebMock).to(have_requested(:post, "#{base}/issues").with { |req| !req.body.include?('custom_fields') })
      end
    end

    # Pylon takes `state` and `type` on an update only, and Forest has one
    # read-only flag per column to say so with.
    describe '#create naming a field Pylon only takes on an update' do
      it 'refuses the create, naming the field' do
        expect { issues.create(nil, 'title' => 'Boom', 'state' => 'closed') }
          .to raise_error(UnsupportedWriteError, /'state' cannot be set here on a PylonIssue/)
      end

      it 'asks for nothing when the field carries no value' do
        stub_request(:post, "#{base}/issues").to_return(json('data' => issue_payload('i1')))

        issues.create(nil, 'title' => 'Boom', 'state' => nil, 'type' => '')

        expect(WebMock).to have_requested(:post, "#{base}/issues").with(body: { 'title' => 'Boom' })
      end
    end

    describe '#update' do
      it 'patches the record the filter names, without reading it back first' do
        stub_request(:patch, "#{base}/issues/i1").to_return(json('data' => issue_payload('i1')))

        issues.update(nil, id_filter(operators::EQUAL, 'i1'), 'title' => 'Louder')

        expect(WebMock).to have_requested(:patch, "#{base}/issues/i1").with(body: { 'title' => 'Louder' })
        expect(WebMock).not_to have_requested(:get, "#{base}/issues/i1")
      end

      it 'patches every record an `in` filter names' do
        stub_request(:patch, "#{base}/issues/i1").to_return(json('data' => issue_payload('i1')))
        stub_request(:patch, "#{base}/issues/i2").to_return(json('data' => issue_payload('i2')))

        issues.update(nil, id_filter(operators::IN, %w[i1 i2]), 'state' => 'closed')

        expect(WebMock).to have_requested(:patch, "#{base}/issues/i1").with(body: { 'state' => 'closed' })
        expect(WebMock).to have_requested(:patch, "#{base}/issues/i2").with(body: { 'state' => 'closed' })
      end

      it 'sends nothing when every key of the patch is read-only' do
        issues.update(nil, id_filter(operators::EQUAL, 'i1'), 'number' => 9, 'link' => 'http://x')

        expect(WebMock).not_to have_requested(:patch, "#{base}/issues/i1")
      end

      # The cap bounds a write, and a patch naming nothing writable is not one:
      # it is settled before the ids are, so the selection is never resolved and
      # never refused for its width.
      it 'sends nothing, and refuses nothing, when the patch is read-only over a wide selection' do
        ids = Array.new(21) { |index| "i#{index}" }

        expect { issues.update(nil, id_filter(operators::IN, ids), 'number' => 9) }.not_to raise_error
        expect(WebMock).not_to have_requested(:patch, %r{/issues/})
      end

      # The scope the operator's role carries rides along as an `and`, so the ids
      # are resolved through the collection's own read and a record the scope
      # excludes is never written to.
      it 'resolves the ids through a read when the filter carries more than an id' do
        stub_request(:get, "#{base}/issues/i1").to_return(json('data' => issue_payload('i1', 'state' => 'closed')))

        issues.update(nil, filter(condition_tree: branch('And', [leaf('id', operators::EQUAL, 'i1'),
                                                                 leaf('state', operators::EQUAL, 'new')])),
                      'title' => 'Louder')

        expect(WebMock).to have_requested(:get, "#{base}/issues/i1")
        expect(WebMock).not_to have_requested(:patch, "#{base}/issues/i1")
      end
    end

    # The record a write answers with is discarded here, so a patch Pylon
    # answers with no body at all wrote the record just the same — and the rest
    # of the selection is written rather than aborted on it.
    describe '#update answered with no record' do
      it 'writes every record of the selection' do
        stub_request(:patch, "#{base}/issues/i1").to_return(status: 204)
        stub_request(:patch, "#{base}/issues/i2").to_return(json('data' => nil))

        issues.update(nil, id_filter(operators::IN, %w[i1 i2]), 'state' => 'closed')

        expect(WebMock).to have_requested(:patch, "#{base}/issues/i1")
        expect(WebMock).to have_requested(:patch, "#{base}/issues/i2")
      end
    end

    # One record is one request, so a failure on the k-th leaves the k-1 before
    # it written and written for good: the error names them, where the API error
    # alone would read as "the write failed, nothing happened" and a retry of the
    # whole selection would write them twice.
    describe 'a write failing partway through the selection' do
      it 'names the records already written' do
        stub_request(:patch, "#{base}/issues/i1").to_return(json('data' => issue_payload('i1')))
        stub_request(:patch, "#{base}/issues/i2").to_return(json({ 'message' => 'state is invalid' }, 422))

        expect { issues.update(nil, id_filter(operators::IN, %w[i1 i2]), 'state' => 'closed') }
          .to raise_error(PartialWriteError, /1 of 2 PylonIssue records were updated and then 'i2' failed/)
        expect(WebMock).to have_requested(:patch, "#{base}/issues/i1")
      end

      it 'names the records already deleted' do
        stub_request(:delete, "#{base}/issues/i1").to_return(status: 204)
        stub_request(:delete, "#{base}/issues/i2").to_return(json({ 'message' => 'gone' }, 404))

        expect { issues.delete(nil, id_filter(operators::IN, %w[i1 i2])) }
          .to raise_error(PartialWriteError, /records already deleted are i1/)
      end

      # Nothing was written, so the failure is the whole of what happened and
      # travels as the error Pylon answered with.
      it 'raises the API error itself when the first record failed' do
        stub_request(:delete, "#{base}/issues/i1").to_return(json({ 'message' => 'gone' }, 404))

        expect { issues.delete(nil, id_filter(operators::IN, %w[i1 i2])) }
          .to raise_error(APIError, %r{delete\(issues/i1\)})
      end
    end

    describe '#update naming a field Pylon only takes on a create' do
      it 'refuses the update when the operator changed it' do
        stub_request(:get, "#{base}/issues/i1").to_return(json('data' => issue_payload('i1')))

        expect { issues.update(nil, id_filter(operators::EQUAL, 'i1'), 'body_html' => '<p>louder</p>') }
          .to raise_error(UnsupportedWriteError, /'body_html' cannot be set here on a PylonIssue/)
      end

      # A form resending an untouched field asks for nothing, so the rest of the
      # edit goes through rather than erroring on a value nobody changed.
      it 'drops it, and writes the rest, when it holds the value already stored' do
        stub_request(:get, "#{base}/issues/i1").to_return(json('data' => issue_payload('i1')))
        stub_request(:patch, "#{base}/issues/i1").to_return(json('data' => issue_payload('i1')))

        issues.update(nil, id_filter(operators::EQUAL, 'i1'),
                      'body_html' => '<p>boom</p>', 'title' => 'Louder')

        expect(WebMock).to have_requested(:patch, "#{base}/issues/i1").with(body: { 'title' => 'Louder' })
      end

      # An unchecked box over a record holding nothing is not an edit: Pylon
      # returns a null where the form sends `false`, and refusing that pair
      # would fail every edit whose form carries one.
      it 'drops a boolean left false over a record holding nothing' do
        stub_request(:get, "#{base}/issues/i1").to_return(json('data' => issue_payload('i1')))
        stub_request(:patch, "#{base}/issues/i1").to_return(json('data' => issue_payload('i1')))

        issues.update(nil, id_filter(operators::EQUAL, 'i1'), 'author_unverified' => false, 'title' => 'Louder')

        expect(WebMock).to have_requested(:patch, "#{base}/issues/i1").with(body: { 'title' => 'Louder' })
      end

      # Over a record holding `true` the same `false` is the operator unchecking
      # the box: Pylon cannot write it, and dropping it would report an edit it
      # never performed.
      it 'refuses a boolean the operator unchecked' do
        stub_request(:get, "#{base}/issues/i1")
          .to_return(json('data' => issue_payload('i1', 'author_unverified' => true)))

        expect { issues.update(nil, id_filter(operators::EQUAL, 'i1'), 'author_unverified' => false) }
          .to raise_error(UnsupportedWriteError, /'author_unverified' cannot be set here on a PylonIssue/)
      end

      # Same story for a value cleared rather than unchecked: an empty body over
      # a stored one is an edit, where an empty body over an empty one is not.
      it 'refuses a string the operator cleared' do
        stub_request(:get, "#{base}/issues/i1").to_return(json('data' => issue_payload('i1')))

        expect { issues.update(nil, id_filter(operators::EQUAL, 'i1'), 'body_html' => '') }
          .to raise_error(UnsupportedWriteError, /'body_html' cannot be set here on a PylonIssue/)
      end

      # The markup an editor hands back may be the markup it was given,
      # re-indented. Refusing that would name a field the operator never touched.
      it 'drops a string the editor only re-indented' do
        stub_request(:get, "#{base}/issues/i1").to_return(json('data' => issue_payload('i1')))
        stub_request(:patch, "#{base}/issues/i1").to_return(json('data' => issue_payload('i1')))

        issues.update(nil, id_filter(operators::EQUAL, 'i1'),
                      'body_html' => "  <p>boom</p>\n", 'title' => 'Louder')

        expect(WebMock).to have_requested(:patch, "#{base}/issues/i1").with(body: { 'title' => 'Louder' })
      end

      # Both offending fields at once: refusing them one at a time would have the
      # operator undo one, retry, and learn about the next.
      it 'names every field of the wrong direction in one message' do
        stub_request(:get, "#{base}/issues/i1")
          .to_return(json('data' => issue_payload('i1', 'author_unverified' => true)))

        expect do
          issues.update(nil, id_filter(operators::EQUAL, 'i1'),
                        'body_html' => '<p>louder</p>', 'author_unverified' => false)
        end.to raise_error(UnsupportedWriteError, /'body_html', 'author_unverified' cannot be set here/)
      end

      # The filter was already resolved into ids, so reading it again would spend
      # the same requests twice and, carrying no page of its own, walk every
      # record it matches instead of the one about to be written.
      it 'reads the stored value by id rather than running the filter a second time' do
        contact = { 'id' => 'c1', 'name' => 'Ada', 'email' => 'ada@acme.test' }
        stub_request(:post, "#{base}/contacts/search").to_return(json('data' => [contact]))
        stub_request(:get, "#{base}/contacts/c1").to_return(json('data' => contact))
        stub_request(:patch, "#{base}/contacts/c1").to_return(json('data' => contact))

        contacts.update(nil, filter(condition_tree: leaf('name', operators::EQUAL, 'Ada')),
                        'email' => 'ada@acme.test', 'avatar_url' => 'http://x')

        expect(WebMock).to have_requested(:post, "#{base}/contacts/search").once
        expect(WebMock).to have_requested(:get, "#{base}/contacts/c1")
        expect(WebMock).to have_requested(:patch, "#{base}/contacts/c1").with(body: { 'avatar_url' => 'http://x' })
      end
    end

    describe '#delete' do
      it 'deletes every record the filter names' do
        stub_request(:delete, "#{base}/issues/i1").to_return(status: 204)
        stub_request(:delete, "#{base}/issues/i2").to_return(status: 204)

        issues.delete(nil, id_filter(operators::IN, %w[i1 i2]))

        expect(WebMock).to have_requested(:delete, "#{base}/issues/i1")
        expect(WebMock).to have_requested(:delete, "#{base}/issues/i2")
      end

      it 'deletes nothing when the filter matches no record' do
        stub_request(:post, "#{base}/accounts/search").to_return(json('data' => []))

        accounts.delete(nil, filter(condition_tree: leaf('name', operators::EQUAL, 'Nope')))

        expect(WebMock).not_to have_requested(:delete, %r{/accounts/})
      end
    end

    # One request per record against a budget of ten to twenty per minute: past
    # the cap the write is refused rather than applied to the first records and
    # reported as done for the whole selection.
    describe 'a write reaching more records than one pass covers' do
      it 'refuses it before spending a single request' do
        ids = Array.new(21) { |index| "i#{index}" }

        expect { issues.delete(nil, id_filter(operators::IN, ids)) }
          .to raise_error(UnsupportedWriteError, /applies to 21 PylonIssue records/)
        expect(WebMock).not_to have_requested(:delete, %r{/issues/})
      end

      it 'refuses it when the count only shows once the filter is resolved' do
        stub_request(:post, "#{base}/accounts/search")
          .to_return(json('data' => Array.new(21) { |index| { 'id' => "a#{index}", 'name' => 'Acme' } }))

        expect { accounts.delete(nil, filter(condition_tree: leaf('name', operators::EQUAL, 'Acme'))) }
          .to raise_error(UnsupportedWriteError, /applies to 21 PylonAccount records/)
        expect(WebMock).not_to have_requested(:delete, %r{/accounts/})
      end

      # The ids a filter names are not the records the write applies to when the
      # filter narrows them further: the collections filtering `id` server-side
      # learn the real count in one request, and write it.
      it 'writes the records a narrowed selection really matches' do
        stub_request(:post, "#{base}/accounts/search")
          .to_return(json('data' => [{ 'id' => 'a1', 'name' => 'Acme' }]))
        stub_request(:patch, "#{base}/accounts/a1").to_return(json('data' => { 'id' => 'a1' }))

        ids = Array.new(25) { |index| "a#{index}" }
        accounts.update(nil, filter(condition_tree: branch('And', [leaf('id', operators::IN, ids),
                                                                   leaf('name', operators::EQUAL, 'Acme')])),
                        'name' => 'Acme Inc')

        expect(WebMock).to have_requested(:patch, "#{base}/accounts/a1").with(body: { 'name' => 'Acme Inc' })
      end

      # An issue is read one request per named id, so past the fan-out the
      # resolution would stop short and the write would cover part of the
      # selection. Refused — as the ids it names, never as records it was found
      # to apply to.
      it 'refuses more named ids than the collection can resolve, without claiming they all match' do
        ids = Array.new(25) { |index| "i#{index}" }

        expect do
          issues.update(nil, filter(condition_tree: branch('And', [leaf('id', operators::IN, ids),
                                                                   leaf('state', operators::EQUAL, 'new')])),
                        'title' => 'Louder')
        end.to raise_error(UnsupportedWriteError, /names 25 PylonIssue records and filters them further/)
        expect(WebMock).not_to have_requested(:get, %r{/issues/})
      end

      # "Select all except these" reaches PylonIssue as `id not_in`, which its
      # endpoint cannot filter: the read refuses it, and so does the delete. The
      # message names that selection rather than the `and`/`or` of a filter the
      # operator never wrote.
      it 'refuses an excluding selection on the collection that cannot filter an id' do
        expect { issues.delete(nil, id_filter(operators::NOT_IN, %w[i1])) }
          .to raise_error(UnsupportedOperatorError,
                          /Select the records to act on rather than the ones to leave out/)
      end
    end

    describe 'a verb Pylon exposes no endpoint for' do
      it 'refuses to create a user' do
        expect { users.create(nil, 'name' => 'Ada') }
          .to raise_error(UnsupportedWriteError, /A PylonUser record cannot be created/)
      end

      it 'refuses to delete a user' do
        expect { users.delete(nil, id_filter(operators::EQUAL, 'u1')) }
          .to raise_error(UnsupportedWriteError, /A PylonUser record cannot be deleted/)
      end

      it 'refuses to delete a team' do
        expect { teams.delete(nil, id_filter(operators::EQUAL, 't1')) }
          .to raise_error(UnsupportedWriteError, /A PylonTeam record cannot be deleted/)
      end
    end

    describe 'the collections read through their own endpoints' do
      it 'writes an account type under the name Pylon takes it as' do
        stub_request(:post, "#{base}/accounts").to_return(json('data' => { 'id' => 'a1', 'name' => 'Acme' }))

        accounts.create(nil, 'name' => 'Acme', 'type' => 'customer', 'domains' => %w[acme.test])

        expect(WebMock).to have_requested(:post, "#{base}/accounts")
          .with(body: { 'name' => 'Acme', 'account_type' => 'customer', 'domains' => %w[acme.test] })
      end

      it 'refuses to disable an account that does not exist yet' do
        expect { accounts.create(nil, 'name' => 'Acme', 'is_disabled' => true) }
          .to raise_error(UnsupportedWriteError, /'is_disabled' cannot be set here on a PylonAccount/)
      end

      # An account is created enabled, which is what the form asks for when the
      # box is left unchecked: the create it produces is the one requested.
      it 'creates an account whose update-only boolean is left false' do
        stub_request(:post, "#{base}/accounts").to_return(json('data' => { 'id' => 'a1', 'name' => 'Acme' }))

        accounts.create(nil, 'name' => 'Acme', 'is_disabled' => false)

        expect(WebMock).to have_requested(:post, "#{base}/accounts").with(body: { 'name' => 'Acme' })
      end

      # `POST /contacts` takes the primary address and `PATCH /contacts/{id}` the
      # list, so one payload never carries both projections of the addresses.
      it 'creates a contact with its primary address' do
        stub_request(:post, "#{base}/contacts").to_return(json('data' => { 'id' => 'c1', 'name' => 'Ada' }))

        contacts.create(nil, 'name' => 'Ada', 'email' => 'ada@acme.test', 'emails' => [])

        expect(WebMock).to have_requested(:post, "#{base}/contacts")
          .with(body: { 'name' => 'Ada', 'email' => 'ada@acme.test' })
      end

      it 'refuses to change the primary address of an existing contact' do
        stub_request(:get, "#{base}/contacts/c1")
          .to_return(json('data' => { 'id' => 'c1', 'name' => 'Ada', 'email' => 'ada@acme.test' }))

        expect { contacts.update(nil, id_filter(operators::EQUAL, 'c1'), 'email' => 'new@acme.test') }
          .to raise_error(UnsupportedWriteError, /'email' cannot be set here on a PylonContact/)
      end

      it 'patches a contact' do
        stub_request(:patch, "#{base}/contacts/c1").to_return(json('data' => { 'id' => 'c1', 'name' => 'Ada' }))

        contacts.update(nil, id_filter(operators::EQUAL, 'c1'), 'name' => 'Ada', 'account_id' => 'a1')

        expect(WebMock).to have_requested(:patch, "#{base}/contacts/c1")
          .with(body: { 'name' => 'Ada', 'account_id' => 'a1' })
      end

      it 'replaces the members of a team' do
        stub_request(:patch, "#{base}/teams/t1").to_return(json('data' => { 'id' => 't1', 'name' => 'Support' }))

        teams.update(nil, id_filter(operators::EQUAL, 't1'), 'name' => 'Support', 'user_ids' => %w[u1 u2])

        expect(WebMock).to have_requested(:patch, "#{base}/teams/t1")
          .with(body: { 'name' => 'Support', 'user_ids' => %w[u1 u2] })
      end

      it 'patches the status of a user' do
        stub_request(:patch, "#{base}/users/u1").to_return(json('data' => { 'id' => 'u1', 'name' => 'Ada' }))

        users.update(nil, id_filter(operators::EQUAL, 'u1'), 'status' => 'away', 'email' => 'ada@acme.test')

        expect(WebMock).to have_requested(:patch, "#{base}/users/u1").with(body: { 'status' => 'away' })
      end
    end
  end
end
