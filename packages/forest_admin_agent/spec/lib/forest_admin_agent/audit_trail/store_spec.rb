require 'spec_helper'
require 'tempfile'

module ForestAdminAgent
  module AuditTrail
    describe Store do
      let(:db) { Tempfile.new(['audit', '.sqlite3']) }
      let(:store) { described_class.new(database: { adapter: 'sqlite3', database: db.path }) }

      after do
        Sql::AuditConnectionBase.disconnect!
        db.close!
      end

      def record(over = {})
        AuditRecord.new(
          operation: 'update', collection: 'accounts', record_id: '1', status: Recording::DONE,
          previous_values: { 'status' => 'open' }, new_values: { 'status' => 'closed' },
          timestamp: '2026-01-02T03:04:05.000Z', user_id: 42, correlation_key: 'req-1', **over
        )
      end

      def matching_fields(fields)
        store.list_by_record(collection: 'accounts', record_id: '1', fields: fields).map(&:new_values)
      end

      def connection
        Sql::AuditConnectionBase.connection
      end

      it 'creates the audit table with the expected columns on first write' do
        store.append(record)

        expect(store.send(:model).column_names.sort).to eq(
          %w[action_name collection correlation_key id new_values operation previous_record_id previous_values
             record_id status timestamp user_email user_first_name user_id user_last_name]
        )
      end

      # An action row uses the two sides for what went in and what came back.
      it 'persists a smart-action row, submitted form and answer included' do
        store.append(record(operation: 'action', previous_values: { 'amount' => 30 },
                            new_values: { 'type' => 'Success', 'message' => 'Refunded' }))

        audit = store.list_by_record(collection: 'accounts', record_id: '1').first
        expect(audit.operation).to eq('action')
        expect(audit.previous_values).to eq({ 'amount' => 30 })
        expect(audit.new_values).to eq({ 'type' => 'Success', 'message' => 'Refunded' })
      end

      it 'persists and reads back a record, decoding the JSON columns' do
        store.append(record)

        audit = store.list_by_record(collection: 'accounts', record_id: '1').first
        expect(audit.operation).to eq('update')
        expect(audit.user_id).to eq(42)
        expect(audit.previous_values).to eq({ 'status' => 'open' })
        expect(audit.new_values).to eq({ 'status' => 'closed' })
      end

      it 'returns a record history oldest-first, scoped to the record, honoring skip/limit' do
        store.append(record(timestamp: '2026-01-02T03:04:06.000Z', correlation_key: 'b'))
        store.append(record(timestamp: '2026-01-02T03:04:05.000Z', correlation_key: 'a'))
        store.append(record(record_id: '2', correlation_key: 'other'))

        history = store.list_by_record(collection: 'accounts', record_id: '1')
        expect(history.map(&:correlation_key)).to eq(%w[a b])

        page = store.list_by_record(collection: 'accounts', record_id: '1', skip: 1, limit: 1)
        expect(page.map(&:correlation_key)).to eq(['b'])
      end

      it 'sorts newest first when order is desc, breaking ties by insertion order' do
        store.append(record(timestamp: '2026-01-02T03:04:05.000Z', correlation_key: 'a'))
        store.append(record(timestamp: '2026-01-02T03:04:06.000Z', correlation_key: 'b'))
        store.append(record(timestamp: '2026-01-02T03:04:05.000Z', correlation_key: 'a2'))

        history = store.list_by_record(collection: 'accounts', record_id: '1', order: 'desc')
        expect(history.map(&:correlation_key)).to eq(%w[b a a2])
      end

      # A cursor survives writes between reads that would shift an offset: nothing repeats, nothing is skipped.
      it 'continues past a given row in either order, whatever was written since' do
        store.append(record(timestamp: '2026-01-02T03:04:05.000Z', correlation_key: 'a'))
        store.append(record(timestamp: '2026-01-02T03:04:06.000Z', correlation_key: 'b'))
        store.append(record(timestamp: '2026-01-02T03:04:05.000Z', correlation_key: 'a2'))

        newest = store.list_by_record(collection: 'accounts', record_id: '1', order: 'desc', limit: 2)
        store.append(record(timestamp: '2026-01-02T03:04:07.000Z', correlation_key: 'late'))
        rest = store.list_by_record(collection: 'accounts', record_id: '1', order: 'desc',
                                    after: newest.last.to_h.slice(:timestamp, :id))
        oldest = store.list_by_record(collection: 'accounts', record_id: '1', limit: 1)
        later = store.list_by_record(collection: 'accounts', record_id: '1',
                                     after: oldest.last.to_h.slice(:timestamp, :id))

        expect((newest + rest).map(&:correlation_key)).to eq(%w[b a a2])
        expect((oldest + later).map(&:correlation_key)).to eq(%w[a a2 b late])
      end

      it 'filters by user_ids and inclusive timestamp range' do
        store.append(record(timestamp: '2026-01-02T03:04:05.000Z', user_id: 7, correlation_key: 'keep'))
        store.append(record(timestamp: '2026-01-02T03:04:09.000Z', user_id: 7, correlation_key: 'late'))
        store.append(record(timestamp: '2026-01-02T03:04:05.000Z', user_id: 9, correlation_key: 'other'))

        history = store.list_by_record(
          collection: 'accounts', record_id: '1', user_ids: [7],
          start_timestamp: '2026-01-02T03:04:04.000Z', end_timestamp: '2026-01-02T03:04:06.000Z'
        )
        expect(history.map(&:correlation_key)).to eq(['keep'])
      end

      it 'keeps only the given operations, in the rows, the count and the authors alike' do
        store.append(record(operation: 'update', user_id: 7, correlation_key: 'u'))
        store.append(record(operation: 'delete', user_id: 8, correlation_key: 'd'))
        store.append(record(operation: 'action', user_id: 9, correlation_key: 'a'))

        filters = { collection: 'accounts', record_id: '1', operations: %w[update action] }

        expect(store.list_by_record(**filters).map(&:correlation_key)).to eq(%w[u a])
        expect(store.count_by_record(**filters)).to eq(2)
        expect(store.authors_by_record(**filters).map { |author| author[:user_id] }).to contain_exactly(7, 9)
      end

      describe '#list_timeline' do
        def timeline(**query)
          store.list_timeline(collections: %w[accounts orders], limit: 10, **query).map(&:correlation_key)
        end

        before do
          store.append(record(timestamp: '2026-01-02T03:04:05.000Z', correlation_key: 'a'))
          store.append(record(timestamp: '2026-01-02T03:04:06.000Z', correlation_key: 'b', collection: 'orders'))
          store.append(record(timestamp: '2026-01-02T03:04:06.000Z', correlation_key: 'c'))
          store.append(record(timestamp: '2026-01-02T03:04:07.000Z', correlation_key: 'hidden', collection: 'staff'))
        end

        it 'lists every given collection newest first, ties by descending id' do
          expect(timeline).to eq(%w[c b a])
        end

        it 'walks oldest first on order asc, ties by ascending id' do
          expect(timeline(order: 'asc')).to eq(%w[a b c])
        end

        it 'matches nothing for an empty collection list' do
          expect(store.list_timeline(collections: [], limit: 10)).to eq([])
        end

        it 'keeps the rows at an inclusive bound, minus the ids already served there' do
          served = store.list_timeline(collections: %w[accounts orders], limit: 10)
                        .find { |row| row.correlation_key == 'c' }

          expect(timeline(before: '2026-01-02T03:04:06.000Z', exclude_ids: [served.id])).to eq(%w[b a])
          expect(timeline(order: 'asc', after: '2026-01-02T03:04:06.000Z')).to eq(%w[b c])
        end

        it 'keeps the tighter of a cursor bound and the date filter on its side' do
          expect(timeline(before: '2026-01-02T03:04:06.000Z', end_timestamp: '2026-01-02T03:04:05.000Z')).to eq(%w[a])
          expect(timeline(before: '2026-01-02T03:04:05.000Z', end_timestamp: '2026-01-02T03:04:06.000Z')).to eq(%w[a])
        end

        it 'applies the operations and author filters' do
          store.append(record(operation: 'delete', user_id: 7, correlation_key: 'd'))

          expect(timeline(operations: %w[delete])).to eq(%w[d])
          expect(timeline(user_ids: [7])).to eq(%w[d])
        end
      end

      it 'lists the distinct authors of the timeline across the given collections only' do
        store.append(record(user_id: 7, user_first_name: 'Jane'))
        store.append(record(user_id: 8, collection: 'orders'))
        store.append(record(user_id: 9, collection: 'staff'))

        authors = store.timeline_users(collections: %w[accounts orders])

        expect(authors.map { |author| author[:user_id] }).to contain_exactly(7, 8)
        expect(authors.find { |author| author[:user_id] == 7 }).to include(user_first_name: 'Jane')
      end

      it 'counts matches independently of skip/limit, respecting filters' do
        store.append(record(user_id: 7))
        store.append(record(user_id: 7))
        store.append(record(user_id: 9))

        expect(store.count_by_record(collection: 'accounts', record_id: '1')).to eq(3)
        expect(store.count_by_record(collection: 'accounts', record_id: '1', user_ids: [7])).to eq(2)
      end

      it 'lists entries under a correlation key for the record, scoped and oldest first' do
        store.append(record(record_id: '1', correlation_key: 'req-1', timestamp: '2026-01-01T00:00:02.000Z'))
        store.append(record(record_id: '1', correlation_key: 'req-1', timestamp: '2026-01-01T00:00:01.000Z'))
        store.append(record(record_id: '1', correlation_key: 'req-2'))
        store.append(record(record_id: '2', correlation_key: 'req-1'))

        history = store.list_by_correlation(collection: 'accounts', record_id: '1', correlation_key: 'req-1')
        expect(history.map(&:timestamp)).to eq(['2026-01-01T00:00:01.000Z', '2026-01-01T00:00:02.000Z'])
      end

      it 'lists a flat history across multiple correlation keys, oldest first' do
        store.append(record(correlation_key: 'a', timestamp: '2026-01-03T00:00:00.000Z'))
        store.append(record(correlation_key: 'b', timestamp: '2026-01-01T00:00:00.000Z'))
        store.append(record(correlation_key: 'a', timestamp: '2026-01-02T00:00:00.000Z'))
        store.append(record(correlation_key: 'c', timestamp: '2026-01-04T00:00:00.000Z'))

        history = store.list_by_correlations(collection: 'accounts', record_id: '1', correlation_keys: %w[a b])
        expect(history.map(&:timestamp)).to eq(
          ['2026-01-01T00:00:00.000Z', '2026-01-02T00:00:00.000Z', '2026-01-03T00:00:00.000Z']
        )
      end

      it 'returns an empty array for an empty correlation key list' do
        store.append(record(correlation_key: 'a'))

        expect(store.list_by_correlations(collection: 'accounts', record_id: '1', correlation_keys: [])).to eq([])
      end

      it 'tracks applied migrations beside the table they built, and is idempotent across stores' do
        store.append(record)
        described_class.new(database: { adapter: 'sqlite3', database: db.path }).append(record)

        names = connection.select_values('SELECT name FROM audit_logs_migration ORDER BY name')
        expect(names).to eq(['001-create-audit-logs'])
      end

      # One tracker per audited table, so a second store does not read the first one's history as its own.
      it 'migrates a second table in the same database, tracking it separately' do
        store.append(record)
        other = described_class.new(database: { adapter: 'sqlite3', database: db.path }, table_name: 'other_logs')

        expect { other.append(record) }.not_to raise_error
        expect(other.list_by_record(collection: 'accounts', record_id: '1').size).to eq(1)
        expect(connection.indexes('other_logs').map(&:name)).to include('other_logs_record_id')
        expect(connection.select_values('SELECT name FROM other_logs_migration')).to eq(['001-create-audit-logs'])
      end

      # Every write sets it, so a row without one is a bug rather than a row quietly claiming to be done.
      it 'refuses a row with no status' do
        expect { store.append(record(status: nil)) }.to raise_error(ActiveRecord::NotNullViolation)
      end

      it 'binds each store to its own model class instead of mutating a shared one' do
        other = described_class.new(database: { adapter: 'sqlite3', database: db.path })
        store.append(record(correlation_key: 'main'))
        other.append(record(correlation_key: 'other'))

        # No shared mutable model: AuditLog is an abstract template, each store owns a distinct subclass.
        expect(Sql::AuditLog.abstract_class?).to be(true)
        expect(store.send(:model)).not_to equal(other.send(:model))
        expect(store.send(:model).table_name).to eq('audit_logs')
        expect(store.list_by_record(collection: 'accounts', record_id: '1').map(&:correlation_key))
          .to eq(%w[main other])
      end

      it 'lists only entries whose diff touched one of the given fields' do
        store.append(record(previous_values: { 'status' => 'open' }, new_values: { 'status' => 'closed' }))
        store.append(record(previous_values: { 'note' => 'a' }, new_values: { 'note' => 'b' }))
        # Added key: it exists on the new side only, so both sides have to be searched.
        store.append(record(previous_values: {}, new_values: { 'tags' => ['x'] }))

        expect(matching_fields(%w[status])).to eq([{ 'status' => 'closed' }])
        expect(matching_fields(%w[tags])).to eq([{ 'tags' => ['x'] }])
        expect(matching_fields(%w[status note]).size).to eq(2)
        expect(matching_fields(%w[missing])).to eq([])
      end

      it 'treats a field name holding a dot as a whole key, not a path' do
        store.append(record(previous_values: { 'address.city' => 'Paris' },
                            new_values: { 'address.city' => 'Lyon' }))
        store.append(record(previous_values: { 'address' => { 'city' => 'Paris' } },
                            new_values: { 'address' => { 'city' => 'Lyon' } }))

        expect(matching_fields(['address.city'])).to eq([{ 'address.city' => 'Lyon' }])
        expect(matching_fields(['address'])).to eq([{ 'address' => { 'city' => 'Lyon' } }])
      end

      it 'counts with the field filter applied' do
        store.append(record(previous_values: { 'status' => 'open' }, new_values: { 'status' => 'closed' }))
        store.append(record(previous_values: { 'note' => 'a' }, new_values: { 'note' => 'b' }))

        expect(store.count_by_record(collection: 'accounts', record_id: '1', fields: %w[status])).to eq(1)
      end

      it 'refuses to filter by field on an adapter it has no JSON test for' do
        store.append(record)
        allow(store.send(:model).connection).to receive(:adapter_name).and_return('Informix')

        expect { store.list_by_record(collection: 'accounts', record_id: '1', fields: %w[status]) }
          .to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException, /not supported on informix/)
      end

      describe '#list_since' do
        # A pending row records an attempt whose outcome is unknown; undoing it would invent a state the
        # record was never in.
        it 'leaves a pending row out, so a reconstruction cannot undo a change that may never have happened' do
          store.append(record(timestamp: '2026-01-02T03:04:07.000Z', status: Recording::PENDING,
                              correlation_key: 'attempt'))
          store.append(record(timestamp: '2026-01-02T03:04:07.000Z', correlation_key: 'confirmed'))

          history = store.list_since(collection: 'accounts', record_id: '1',
                                     timestamp: '2026-01-02T03:04:06.000Z')

          expect(history.map(&:correlation_key)).to eq(['confirmed'])
        end

        # They are evidence, and `status` tells the reader what they are.
        it 'keeps them in the history, where the payload says what they are' do
          store.append(record(status: Recording::PENDING))

          expect(store.list_by_record(collection: 'accounts', record_id: '1').map(&:status)).to eq(['pending'])
        end

        it 'returns entries strictly newer than the instant, newest first' do
          store.append(record(timestamp: '2026-01-02T03:04:05.000Z', correlation_key: 'older'))
          store.append(record(timestamp: '2026-01-02T03:04:06.000Z', correlation_key: 'at'))
          store.append(record(timestamp: '2026-01-02T03:04:07.000Z', correlation_key: 'newer'))

          history = store.list_since(collection: 'accounts', record_id: '1',
                                     timestamp: '2026-01-02T03:04:06.000Z')

          expect(history.map(&:correlation_key)).to eq(['newer'])
        end

        it 'breaks ties on equal timestamps by reverse insertion order' do
          store.append(record(timestamp: '2026-01-02T03:04:07.000Z', correlation_key: 'first'))
          store.append(record(timestamp: '2026-01-02T03:04:07.000Z', correlation_key: 'second'))

          history = store.list_since(collection: 'accounts', record_id: '1',
                                     timestamp: '2026-01-02T03:04:06.000Z')

          expect(history.map(&:correlation_key)).to eq(%w[second first])
        end
      end

      describe 'the pending/confirm protocol' do
        it 'inserts rows and hands their ids back, in order' do
          ids = store.append_all([record(correlation_key: 'a'), record(correlation_key: 'b')])

          expect(ids.size).to eq(2)
          expect(store.list_by_record(collection: 'accounts', record_id: '1').map(&:id)).to eq(ids)
        end

        it 'confirms a pending row into a done one, values included' do
          id = store.append(record(status: Recording::PENDING, previous_values: {}, new_values: {}))

          store.confirm(id, record_id: '9', new_values: { 'status' => 'closed' })

          audit = store.list_by_record(collection: 'accounts', record_id: '9').first
          expect(audit.status).to eq(Recording::DONE)
          expect(audit.new_values).to eq({ 'status' => 'closed' })
        end

        # A write that changed nothing leaves no trace, rather than a row implying it is unaccounted for.
        it 'discards rows by id' do
          ids = store.append_all([record, record])

          store.discard(ids)

          expect(store.list_by_record(collection: 'accounts', record_id: '1')).to be_empty
        end

        it 'accepts a pending create row with no record id yet' do
          id = store.append(record(operation: 'create', record_id: nil, status: Recording::PENDING))

          expect { store.confirm(id, record_id: '7') }.not_to raise_error
          expect(store.list_by_record(collection: 'accounts', record_id: '7').first.operation).to eq('create')
        end

        it 'stores a packed composite id far longer than a varchar would hold' do
          long_id = (1..40).map { |part| "part-#{part}-#{"x" * 20}" }.join('|')
          store.append(record(record_id: long_id))

          expect(store.list_by_record(collection: 'accounts', record_id: long_id).size).to eq(1)
        end
      end

      describe 'searching free text' do
        def matching_search(term)
          store.list_by_record(collection: 'accounts', record_id: '1', search: term).map(&:correlation_key)
        end

        it 'matches a value, case-insensitively and as a substring' do
          store.append(record(correlation_key: 'lyon', new_values: { 'city' => 'Lyon' }))
          store.append(record(correlation_key: 'paris', new_values: { 'city' => 'Paris' }))

          expect(matching_search('lyo')).to eq(['lyon'])
          expect(matching_search('LYON')).to eq(['lyon'])
        end

        # Only the changed leaves of a JSON column are stored, so the match has to reach them.
        it 'reaches a value nested at any depth' do
          store.append(record(correlation_key: 'nested',
                              new_values: { 'address' => { 'city' => 'Lyon', 'zip' => '69001' } }))

          expect(matching_search('Lyon')).to eq(['nested'])
          expect(matching_search('69001')).to eq(['nested'])
        end

        it 'matches a key as well as a value' do
          store.append(record(correlation_key: 'keyed', new_values: { 'first_name' => 'Jo' }))

          expect(matching_search('first_name')).to eq(['keyed'])
        end

        it 'matches the previous side too, not only the new one' do
          store.append(record(correlation_key: 'was', previous_values: { 'city' => 'Lyon' }, new_values: {}))

          expect(matching_search('Lyon')).to eq(['was'])
        end

        it 'matches the action name and who acted' do
          store.append(record(correlation_key: 'refund', operation: 'action', action_name: 'Refund order',
                              previous_values: {}, new_values: {}))
          store.append(record(correlation_key: 'ada', user_first_name: 'Ada', user_last_name: 'Lovelace',
                              user_email: 'ada@test', previous_values: {}, new_values: {}))

          expect(matching_search('refund ord')).to eq(['refund'])
          expect(matching_search('lovelace')).to eq(['ada'])
          expect(matching_search('ada@')).to eq(['ada'])
        end

        # Machine identifiers nobody searches for: matching them turns one term into confusing hits.
        it 'ignores the operation, the correlation key, the record id and the status' do
          store.append(record(correlation_key: 'searchable-key', operation: 'update', record_id: '1',
                              previous_values: {}, new_values: {}))

          expect(matching_search('searchable-key')).to be_empty
          expect(matching_search('update')).to be_empty
          expect(matching_search('done')).to be_empty
        end

        # A search must never confirm a value the trail refused to record.
        it 'never matches a redacted field, by its mask or by the value it hid' do
          store.append(record(correlation_key: 'masked', previous_values: { 'email' => '[redacted]' },
                              new_values: { 'email' => '[redacted]' }))

          expect(matching_search('redacted')).to be_empty
          expect(matching_search('[redacted]')).to be_empty
          expect(matching_search('secret@test')).to be_empty
        end

        it 'treats LIKE wildcards in the term as ordinary characters' do
          store.append(record(correlation_key: 'literal', new_values: { 'code' => '50%_off' }))
          store.append(record(correlation_key: 'other', new_values: { 'code' => 'anything' }))

          expect(matching_search('50%_')).to eq(['literal'])
          expect(matching_search('%')).to eq(['literal'])
        end

        # The values sit in a serialized document, where a quote is escaped: the raw term would never find them.
        it 'finds a value holding a quote, a backslash or a newline' do
          store.append(record(correlation_key: 'quote', new_values: { 'label' => '15" monitor' }))
          store.append(record(correlation_key: 'path', new_values: { 'path' => 'C:\\Users\\ada' }))
          store.append(record(correlation_key: 'multiline', new_values: { 'note' => "first\nsecond" }))

          expect(matching_search('15" monitor')).to eq(['quote'])
          expect(matching_search('C:\\Users')).to eq(['path'])
          expect(matching_search("first\nsecond")).to eq(['multiline'])
        end

        # A bare quote would otherwise match the document's own structure, so every row.
        it 'does not let a bare quote match every row' do
          store.append(record(new_values: { 'city' => 'Lyon' }))

          expect(matching_search('"')).to be_empty
        end

        it 'composes with the other filters, and the count agrees with it' do
          store.append(record(correlation_key: 'keep', user_id: 7, new_values: { 'city' => 'Lyon' }))
          store.append(record(correlation_key: 'wrong-user', user_id: 9, new_values: { 'city' => 'Lyon' }))
          store.append(record(correlation_key: 'wrong-term', user_id: 7, new_values: { 'city' => 'Paris' }))

          expect(store.list_by_record(collection: 'accounts', record_id: '1', search: 'lyon',
                                      user_ids: [7]).map(&:correlation_key)).to eq(['keep'])
          expect(store.count_by_record(collection: 'accounts', record_id: '1', search: 'lyon',
                                       user_ids: [7])).to eq(1)
        end

        it 'narrows the authors it offers to those the term matches' do
          store.append(record(user_id: 7, new_values: { 'city' => 'Lyon' }))
          store.append(record(user_id: 9, new_values: { 'city' => 'Paris' }))

          authors = store.authors_by_record(collection: 'accounts', record_id: '1', search: 'lyon')

          expect(authors.map { |author| author[:user_id] }).to eq([7])
        end
      end

      describe '#authors_by_record' do
        it 'lists the distinct authors of the matching entries, as they were when they acted' do
          store.append(record(user_id: 7, user_first_name: 'Ada', user_last_name: 'L', user_email: 'ada@test'))
          store.append(record(user_id: 7, user_first_name: 'Ada', user_last_name: 'L', user_email: 'ada@test'))
          store.append(record(user_id: 9, user_first_name: 'Bob', user_last_name: 'K', user_email: 'bob@test'))
          store.append(record(record_id: '2', user_id: 11, user_first_name: 'Other'))

          authors = store.authors_by_record(collection: 'accounts', record_id: '1')

          expect(authors).to contain_exactly(
            { user_id: 7, user_first_name: 'Ada', user_last_name: 'L', user_email: 'ada@test' },
            { user_id: 9, user_first_name: 'Bob', user_last_name: 'K', user_email: 'bob@test' }
          )
        end

        it 'stays inside the active filters but ignores paging' do
          store.append(record(user_id: 7, timestamp: '2026-01-02T03:04:05.000Z'))
          store.append(record(user_id: 9, timestamp: '2026-01-09T03:04:05.000Z'))

          authors = store.authors_by_record(collection: 'accounts', record_id: '1',
                                            end_timestamp: '2026-01-03T00:00:00.000Z')

          expect(authors.map { |author| author[:user_id] }).to eq([7])
        end

        it 'leaves out entries with no author' do
          store.append(record(user_id: nil))

          expect(store.authors_by_record(collection: 'accounts', record_id: '1')).to be_empty
        end
      end

      # establish_connection is class-level: two stores on different databases would silently share one pool.
      it 'refuses a second audit database rather than clobbering the first' do
        store.append(record)
        other = described_class.new(database: { adapter: 'sqlite3', database: ':memory:' })

        expect { other.append(record) }.to raise_error(
          ForestAdminDatasourceToolkit::Exceptions::ForestException, /One agent, one audit database/
        )
      end

      it 'indexes record_id, correlation_key and user_id' do
        store.append(record)

        index_names = connection.indexes('audit_logs').map(&:name)
        expect(index_names).to include(
          'audit_logs_record_id', 'audit_logs_correlation_key', 'audit_logs_user_id'
        )
      end
    end
  end
end
