require 'spec_helper'

module ForestAdminAgent
  module Routes
    module Resources
      include ForestAdminDatasourceToolkit::Schema
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

      describe AuditTrail do
        let(:store) { double('store') }
        let(:permissions) { double('permissions', can?: true, get_scope: nil) }
        let(:collection) do
          build_collection(
            name: 'projects',
            schema: {
              fields: {
                'id' => ColumnSchema.new(
                  column_type: 'Number', is_primary_key: true,
                  filter_operators: [Operators::IN, Operators::EQUAL]
                ),
                'status' => ColumnSchema.new(column_type: 'String'),
                # Read-only, so the capture never records it: the audit snapshots hold writable columns only.
                'created_at' => ColumnSchema.new(column_type: 'Number', is_read_only: true),
                # Nullable, so a row can capture it as nil and still hold the key.
                'budget' => ColumnSchema.new(column_type: 'Number')
              }
            },
            list: [{ 'id' => 4 }]
          )
        end

        def route_with_store(records: [])
          allow(ForestAdminAgent::Facades::Container).to receive(:config_from_cache)
            .and_return({ audit_trail: { store: store } })
          allow(store).to receive_messages(list_by_record: records, count_by_record: records.length,
                                           authors_by_record: [], renamed_from: [])

          route = described_class.new
          context = double('context', collection: collection, caller: build_caller, permissions: permissions)
          allow(route).to receive(:build).and_return(context)
          route
        end

        describe 'state reconstruction' do
          def state_route(entries: [], record: { 'id' => 4, 'status' => 'shipped' })
            allow(ForestAdminAgent::Facades::Container).to receive(:config_from_cache)
              .and_return({ audit_trail: { store: store } })
            allow(store).to receive_messages(list_since: entries, renamed_from: [])
            allow(collection).to receive(:list).and_return([record].compact)

            route = described_class.new
            context = double('context', collection: collection, caller: build_caller, permissions: permissions)
            allow(route).to receive(:build).and_return(context)
            route
          end

          def entry(operation, previous_values = {}, new_values = {})
            ForestAdminAgent::AuditTrail::AuditRecord.new(
              operation: operation, collection: 'projects', record_id: '4',
              previous_values: previous_values, new_values: new_values
            )
          end

          # Through the registered closure rather than the handler, so the wiring is covered too.
          def get_state(route, timestamp: '2026-01-02T10:00:00.000Z', extra: {})
            route.routes['forest_audit_trail_state'][:closure].call(
              { headers: {},
                params: { 'collection_name' => 'projects', 'id' => '4', 'timestamp' => timestamp }.merge(extra) }
            )
          end

          it 'registers the state route' do
            allow(ForestAdminAgent::Facades::Container).to receive(:config_from_cache)
              .and_return({ audit_trail: { store: Object.new } })

            expect(described_class.new.routes).to include('forest_audit_trail_state')
          end

          it 'returns the record with every later entry undone' do
            route = state_route(entries: [entry('update', { 'status' => 'paid' }, { 'status' => 'shipped' })])

            result = get_state(route)

            expect(result[:content]).to eq({ data: { 'id' => 4, 'status' => 'paid' } })
          end

          # Authorization and read are one query: a scoped check followed by an unscoped read would hand
          # back a row the check never covered. The record is read again on the way out, which is the
          # re-check below, not a separate authorization.
          it 'reads the record through the caller scope, in one query' do
            scope = Nodes::ConditionTreeLeaf.new('id', Operators::EQUAL, 4)
            allow(permissions).to receive(:get_scope).and_return(scope)
            route = state_route
            reads = []
            allow(collection).to receive(:list) do |_caller, filter, projection|
              reads << [filter, projection]
              [{ 'id' => 4, 'status' => 'shipped' }]
            end

            get_state(route)

            filter, projection = reads.first
            expect(filter.condition_tree.conditions).to include(scope)
            expect(projection).to include('status')
          end

          it 'refuses a record that exists outside the caller scope' do
            allow(permissions).to receive(:get_scope).and_return(Nodes::ConditionTreeLeaf.new('id',
                                                                                              Operators::EQUAL, 9))
            route = state_route(record: nil)
            # Nothing in scope, but the record does exist without it: someone else's.
            allow(collection).to receive(:list).and_return([], [{ 'id' => 4 }])

            expect { get_state(route) }.to raise_error(Http::Exceptions::NotFoundError)
            expect(store).not_to have_received(:list_since)
          end

          it 'rebuilds a deleted record from its history' do
            allow(permissions).to receive(:get_scope).and_return(Nodes::ConditionTreeLeaf.new('id',
                                                                                              Operators::EQUAL, 4))
            route = state_route(entries: [entry('delete', { 'status' => 'shipped' }, {})], record: nil)
            allow(collection).to receive(:list).and_return([], [])

            expect(get_state(route)[:content][:data]).to eq({ 'status' => 'shipped' })
          end

          # The history route withholds a gone record's captured values from a caller whose scope they fail,
          # and this route is nothing but those values reassembled: without the same test they come back one
          # request away.
          describe 'a deleted record whose reconstruction falls outside the caller scope' do
            def state_of(entries, scope: Nodes::ConditionTreeLeaf.new('status', Operators::EQUAL, 'mine'))
              allow(permissions).to receive(:get_scope).and_return(scope)
              route = state_route(entries: entries, record: nil)
              # Empty in scope and empty without it: the record is gone for good.
              allow(collection).to receive(:list).and_return([])

              get_state(route).dig(:content, :data)
            end

            it 'returns no data when the reconstruction fails the scope' do
              expect(state_of([entry('delete', { 'status' => 'someone else' })])).to be_nil
            end

            it 'returns the reconstruction that passes the scope' do
              expect(state_of([entry('delete', { 'status' => 'mine' })])).to eq({ 'status' => 'mine' })
            end

            it 'serves it whole to a caller no scope applies to' do
              expect(state_of([entry('delete', { 'status' => 'someone else' })], scope: nil))
                .to eq({ 'status' => 'someone else' })
            end

            # Same rule as a row: absent is not the same as passing.
            it 'returns no data when the scope asks about a column the reconstruction cannot answer' do
              state = state_of([entry('delete', { 'status' => 'mine' })],
                               scope: Nodes::ConditionTreeLeaf.new('created_at', Operators::NOT_EQUAL, 'private'))

              expect(state).to be_nil
            end

            # The reconstruction can sit on the far side of a primary-key move this route cannot see, so the
            # requested id does not answer for a key the trail redacted — unlike on a row, which is filed
            # under an id that was true of the side being tested.
            it 'does not let the requested id answer for a redacted primary key' do
              redacted = ForestAdminAgent::AuditTrail::Recording::REDACTED
              state = state_of([entry('delete', { 'id' => redacted, 'status' => 'mine' })],
                               scope: Nodes::ConditionTreeLeaf.new('id', Operators::EQUAL, 4))

              expect(state).to be_nil
            end

            # A read-only primary key is never captured, so nothing else can answer for it and the requested
            # id is what the record was filed under either way.
            it 'still fills a primary key the capture never kept' do
              state = state_of([entry('delete', { 'status' => 'mine' })],
                               scope: Nodes::ConditionTreeLeaf.new('id', Operators::EQUAL, 4))

              expect(state).to eq({ 'status' => 'mine' })
            end

            # A replacement answers for itself, not for the life whose rows these are: the reconstruction is
            # of a record that was already gone, and the caller's claim on the id today says nothing about it.
            it 'keeps withholding when an in-scope record has taken the id since' do
              allow(permissions).to receive(:get_scope)
                .and_return(Nodes::ConditionTreeLeaf.new('status', Operators::EQUAL, 'mine'))
              route = state_route(entries: [entry('delete', { 'status' => 'someone else' })], record: nil)
              # Gone on the way in, in scope and without it; a record of the caller's own under that id after.
              allow(collection).to receive(:list).and_return([], [], [{ 'id' => 4, 'status' => 'mine' }])

              expect(get_state(route).dig(:content, :data)).to be_nil
            end

            # The same read decides the other way round: an id that was gone at the first check can be taken
            # by another record before the second, and that record's owner is not this caller.
            it 'answers 404 when the id was taken by an out-of-scope record while the rows were being read' do
              allow(permissions).to receive(:get_scope)
                .and_return(Nodes::ConditionTreeLeaf.new('status', Operators::EQUAL, 'mine'))
              route = state_route(entries: [entry('delete', { 'status' => 'mine' })], record: nil)
              # Gone on the way in, in scope and without it; someone else's by the time the rows are in hand.
              allow(collection).to receive(:list).and_return([], [], [], [{ 'id' => 4 }])

              expect { get_state(route) }.to raise_error(Http::Exceptions::NotFoundError)
            end

            # The record can be deleted while the audit read is in flight: the check that ran first would
            # otherwise gate a reconstruction nothing protects any more.
            it 'withholds a reconstruction whose record was deleted after the first read' do
              allow(permissions).to receive(:get_scope)
                .and_return(Nodes::ConditionTreeLeaf.new('status', Operators::EQUAL, 'mine'))
              route = state_route(entries: [entry('delete', { 'status' => 'someone else' })],
                                  record: { 'id' => 4, 'status' => 'mine' })
              # In scope on the way in, gone by the time the rows are in hand.
              allow(collection).to receive(:list).and_return([{ 'id' => 4, 'status' => 'mine' }], [], [])

              expect(get_state(route).dig(:content, :data)).to be_nil
            end
          end

          # Rows written before an update moved a writable primary key stay under the id they were true of.
          it 'reconstructs state from every id the record has been filed under' do
            route = state_route
            allow(store).to receive(:renamed_from).and_return([{ id: '1', until: nil, until_row: nil }], [])

            get_state(route)

            expect(store).to have_received(:list_since).with(
              hash_including(record_id: [{ id: '4', until: nil, until_row: nil },
                                         { id: '1', until: nil, until_row: nil }])
            )
          end

          # Strictly after the requested instant: an entry stamped exactly at it belongs to that state.
          it 'asks the store for entries strictly newer than the instant' do
            route = state_route
            get_state(route)

            expect(store).to have_received(:list_since).with(
              collection: 'projects', record_id: [{ id: '4', until: nil, until_row: nil }],
              timestamp: '2026-01-02T10:00:00.000Z'
            )
          end

          it 'returns no data when the record did not exist yet' do
            route = state_route(entries: [entry('create', {}, { 'status' => 'draft' })])

            expect(get_state(route)[:content][:data]).to be_nil
          end

          it 'reads a wall-clock instant in the request timezone' do
            route = state_route
            get_state(route, timestamp: '2026-01-02T08:30', extra: { 'timezone' => 'America/New_York' })

            expect(store).to have_received(:list_since).with(hash_including(timestamp: '2026-01-02T13:30:00.000Z'))
          end

          # Seconds make it parse as ISO-8601, which would silently read it in the server's timezone.
          it 'reads a wall-clock instant carrying seconds in the request timezone too' do
            route = state_route
            get_state(route, timestamp: '2026-01-02T08:30:15', extra: { 'timezone' => 'America/New_York' })

            expect(store).to have_received(:list_since).with(hash_including(timestamp: '2026-01-02T13:30:15.000Z'))
          end

          it 'reads a bare day in the request timezone' do
            route = state_route
            get_state(route, timestamp: '2026-01-02', extra: { 'timezone' => 'America/New_York' })

            expect(store).to have_received(:list_since).with(hash_including(timestamp: '2026-01-02T05:00:00.000Z'))
          end

          it 'honours an explicit offset instead of the request timezone' do
            route = state_route
            get_state(route, timestamp: '2026-01-02T08:30:15+02:00', extra: { 'timezone' => 'America/New_York' })

            expect(store).to have_received(:list_since).with(hash_including(timestamp: '2026-01-02T06:30:15.000Z'))
          end

          it 'rejects a missing timestamp' do
            route = state_route

            expect { get_state(route, timestamp: '') }.to raise_error(
              Http::Exceptions::ValidationError, /Missing timestamp/
            )
          end

          it 'rejects an unparsable timestamp' do
            route = state_route

            expect { get_state(route, timestamp: 'yesterday') }.to raise_error(Http::Exceptions::ValidationError)
          end
        end

        it 'registers the record-history route when an audit_trail store is configured' do
          allow(ForestAdminAgent::Facades::Container).to receive(:config_from_cache)
            .and_return({ audit_trail: { store: Object.new } })

          expect(described_class.new.routes).to include('forest_audit_trail')
        end

        it 'does not register the route when no audit_trail store is configured' do
          allow(ForestAdminAgent::Facades::Container).to receive(:config_from_cache).and_return({})

          expect(described_class.new.routes).not_to include('forest_audit_trail')
        end

        it 'reads the history scoped to the packed id and returns data + filtered count' do
          entry = { operation: 'update', record_id: '4', previous_values: { 'first_name' => 'Jo' } }
          route = route_with_store(records: [double('entry', to_h: entry)])

          # Through the registered closure rather than the handler, so the wiring is covered too.
          result = route.routes['forest_audit_trail'][:closure].call(
            { headers: {}, params: { 'collection_name' => 'projects', 'id' => '4' } }
          )

          expect(store).to have_received(:list_by_record).with(
            collection: 'projects', record_id: [{ id: '4', until: nil, until_row: nil }], skip: 0, limit: 20, order: 'desc'
          )
          expect(store).to have_received(:count_by_record)
            .with(collection: 'projects', record_id: [{ id: '4', until: nil, until_row: nil }])
          # Top-level keys are camelCased for the frontend; nested value hashes keep the column names.
          expect(result[:content]).to eq(
            {
              data: [{ 'operation' => 'update', 'recordId' => '4', 'previousValues' => { 'first_name' => 'Jo' } }],
              meta: { count: 1, availableUsers: [] }
            }
          )
        end

        it 'intersects the record with the permission scope before reading any history' do
          scope = Nodes::ConditionTreeLeaf.new('id', Operators::EQUAL, 4)
          allow(permissions).to receive(:get_scope).and_return(scope)
          route = route_with_store

          route.handle_request({ headers: {}, params: { 'collection_name' => 'projects', 'id' => '4' } })

          # Twice: once before the store read to refuse an out-of-scope record, once after it so the
          # withholding decision is not older than the rows it applies to.
          expect(collection).to have_received(:list).twice do |_caller, filter, _projection|
            expect(filter.condition_tree.conditions).to include(scope)
          end
        end

        it 'returns 404 without touching the store when the record exists outside the caller scope' do
          allow(permissions).to receive(:get_scope).and_return(Nodes::ConditionTreeLeaf.new('id', Operators::EQUAL, 9))
          # Empty under the scope, found without it: the record is someone else's, not a deleted one.
          allow(collection).to receive(:list).and_return([], [{ 'id' => 4 }])
          route = route_with_store

          expect do
            route.handle_request({ headers: {}, params: { 'collection_name' => 'projects', 'id' => '4' } })
          end.to raise_error(Http::Exceptions::NotFoundError)

          expect(store).not_to have_received(:list_by_record)
        end

        it 'still serves the history of a deleted record, which is much of the point of an audit trail' do
          allow(permissions).to receive(:get_scope).and_return(Nodes::ConditionTreeLeaf.new('id', Operators::EQUAL, 4))
          allow(collection).to receive(:list).and_return([])
          entry = ForestAdminAgent::AuditTrail::AuditRecord.new(operation: 'delete', record_id: '4')
          route = route_with_store(records: [entry])

          result = route.handle_request({ headers: {}, params: { 'collection_name' => 'projects', 'id' => '4' } })

          expect(result[:content][:data].first).to include('operation' => 'delete', 'recordId' => '4')
        end

        # A scope can't be evaluated against a record that is gone, so the rows come back — but the column
        # values they captured while it existed still have to pass that scope.
        describe 'a deleted record whose captured values fall outside the caller scope' do
          def audit_entry(operation, previous_values: {}, new_values: {})
            ForestAdminAgent::AuditTrail::AuditRecord.new(
              operation: operation, collection: 'projects', record_id: '4',
              previous_values: previous_values, new_values: new_values
            )
          end

          def history_of(entries, scope: Nodes::ConditionTreeLeaf.new('status', Operators::EQUAL, 'mine'))
            allow(permissions).to receive(:get_scope).and_return(scope)
            # Empty in scope and empty without it: the record is gone for good.
            allow(collection).to receive(:list).and_return([])
            route = route_with_store(records: entries)

            route.handle_request({ headers: {}, params: { 'collection_name' => 'projects', 'id' => '4' } })
                 .dig(:content, :data)
          end

          # The rows are a dead record's. A live one that has since taken the id is a different record, and
          # being allowed to read it is not a claim on what came before it.
          it 'keeps withholding when an in-scope record has taken the id since' do
            allow(permissions).to receive(:get_scope)
              .and_return(Nodes::ConditionTreeLeaf.new('status', Operators::EQUAL, 'mine'))
            # Gone on the way in, in scope and without it; a record of the caller's own under that id after.
            allow(collection).to receive(:list).and_return([], [], [{ 'id' => 4, 'status' => 'mine' }])
            route = route_with_store(records: [audit_entry('delete',
                                                           previous_values: { 'status' => 'someone else' })])

            data = route.handle_request({ headers: {}, params: { 'collection_name' => 'projects', 'id' => '4' } })
                        .dig(:content, :data)

            expect(data.first).to include('operation' => 'delete', 'previousValues' => {})
          end

          # The check that authorized the request ran before these rows were read: an id that was gone then
          # can belong to another record now, and this caller has no claim on that one's history.
          it 'answers 404 when the id was taken by an out-of-scope record while the rows were being read' do
            allow(permissions).to receive(:get_scope)
              .and_return(Nodes::ConditionTreeLeaf.new('status', Operators::EQUAL, 'mine'))
            # Gone on the way in, in scope and without it; someone else's by the time the rows are in hand.
            allow(collection).to receive(:list).and_return([], [], [], [{ 'id' => 4 }])
            route = route_with_store(records: [audit_entry('delete', previous_values: { 'status' => 'mine' })])

            expect do
              route.handle_request({ headers: {}, params: { 'collection_name' => 'projects', 'id' => '4' } })
            end.to raise_error(Http::Exceptions::NotFoundError)
          end

          it 'withholds a delete row whose previous values fail the scope, keeping the row itself' do
            data = history_of([audit_entry('delete', previous_values: { 'status' => 'someone else' })])

            expect(data.first).to include('operation' => 'delete', 'recordId' => '4', 'previousValues' => {})
          end

          it 'keeps a delete row whose previous values pass the scope' do
            data = history_of([audit_entry('delete', previous_values: { 'status' => 'mine' })])

            expect(data.first['previousValues']).to eq({ 'status' => 'mine' })
          end

          # Matched in SQL, a search would still answer what the withholding hides: whether the row comes back,
          # and the count, say whether the withheld value holds the term.
          describe 'searched or filtered by field' do
            def searched(entries, params)
              allow(permissions).to receive(:get_scope)
                .and_return(Nodes::ConditionTreeLeaf.new('status', Operators::EQUAL, 'mine'))
              allow(collection).to receive(:list).and_return([])
              route = route_with_store(records: entries)

              route.handle_request({ headers: {}, params: { 'collection_name' => 'projects', 'id' => '4',
                                                            **params } })[:content]
            end

            def secret_delete
              audit_entry('delete', previous_values: { 'status' => 'someone else secret' })
                .tap { |entry| entry.user_id = 7 }
            end

            it 'finds nothing in a withheld value, and counts nothing' do
              content = searched([secret_delete], 'search' => 'secret')

              expect(content).to include(data: [], meta: { count: 0, availableUsers: [] })
            end

            it 'matches the values it serves' do
              content = searched([audit_entry('delete', previous_values: { 'status' => 'mine' })], 'search' => 'MIN')

              expect(content[:data].map { |row| row['previousValues'] }).to eq([{ 'status' => 'mine' }])
            end

            it 'still matches what stays visible on a withheld row, such as its author' do
              entry = secret_delete.tap { |row| row.user_email = 'jane@acme.io' }

              content = searched([entry], 'search' => 'acme')

              expect(content[:data].first).to include('userEmail' => 'jane@acme.io', 'previousValues' => {})
              expect(content[:meta][:availableUsers]).to eq([{ id: 7, firstName: nil, lastName: nil,
                                                               email: 'jane@acme.io' }])
            end

            it 'lists an author once even when their rows carry different identities' do
              renamed = [secret_delete.tap { |row| row.user_email = 'jane@acme.io' },
                         secret_delete.tap { |row| row.user_email = 'jane@acme.com' }]

              content = searched(renamed, 'search' => 'acme')

              expect(content[:meta][:availableUsers].map { |user| user[:id] }).to eq([7])
            end

            it 'does not match a field only a withheld side touched' do
              content = searched([secret_delete], 'fields' => 'status')

              expect(content[:data]).to eq([])
            end

            it 'reads the rows without the value filters and pages what matched' do
              rows = [audit_entry('create', new_values: { 'status' => 'mine' }),
                      audit_entry('update', previous_values: { 'status' => 'mine' }, new_values: { 'status' => 'mine' })]

              content = searched(rows, 'search' => 'mine', 'userIds' => '12', 'page' => { 'size' => '1', 'number' => '2' })

              expect(store).to have_received(:list_by_record).with(hash_excluding(:search))
              expect(store).to have_received(:list_by_record).with(hash_including(user_ids: [12]))
              expect(content[:data].map { |row| row['operation'] }).to eq(['update'])
              expect(content[:meta]).to eq({ count: 2 })
            end

            # The page cap bounds what is served, not what is scanned: the history is read in batches so
            # a long one is never held in memory whole.
            it 'scans the history in batches, counting across them and keeping only the page' do
              stub_const("#{described_class}::SCAN_BATCH_SIZE", 2)
              rows = Array.new(5) { |index| audit_entry('create', new_values: { 'status' => 'mine', 'n' => index }) }
              allow(permissions).to receive(:get_scope)
                .and_return(Nodes::ConditionTreeLeaf.new('status', Operators::EQUAL, 'mine'))
              allow(collection).to receive(:list).and_return([])
              route = route_with_store
              allow(store).to receive(:list_by_record) { |skip:, **| rows.drop(skip).first(2) }

              content = route.handle_request(
                { headers: {}, params: { 'collection_name' => 'projects', 'id' => '4', 'search' => 'mine',
                                         'page' => { 'size' => '2', 'number' => '2' } } }
              )[:content]

              expect(store).to have_received(:list_by_record).exactly(3).times
              expect(store).to have_received(:list_by_record).with(hash_including(skip: 4, limit: 2))
              expect(content[:data].map { |row| row['newValues']['n'] }).to eq([2, 3])
              expect(content[:meta]).to eq({ count: 5 })
            end
          end

          it 'keeps a create row whose new values pass the scope, and withholds one that does not' do
            data = history_of([audit_entry('create', new_values: { 'status' => 'mine' }),
                               audit_entry('create', new_values: { 'status' => 'someone else' })])

            expect(data.map { |row| row['newValues'] }).to eq([{ 'status' => 'mine' }, {}])
          end

          # Each side of an update is tested on its own values, so the one that can be proven in scope is
          # released and the other is not.
          it 'keeps the side of an update that passes the scope and blanks the one that does not' do
            data = history_of([audit_entry('update', previous_values: { 'status' => 'mine' },
                                                     new_values: { 'status' => 'someone else' })])

            expect(data.first).to include('previousValues' => { 'status' => 'mine' }, 'newValues' => {})
          end

          it 'keeps both sides of an update that stayed in scope' do
            data = history_of([audit_entry('update', previous_values: { 'status' => 'mine' },
                                                     new_values: { 'status' => 'mine' })])

            expect(data.first).to include('previousValues' => { 'status' => 'mine' },
                                          'newValues' => { 'status' => 'mine' })
          end

          # A diff that never carried the scoped column answers for neither side.
          it 'withholds both sides of an update whose diff never touched the scoped column' do
            data = history_of([audit_entry('update', previous_values: { 'created_at' => 1 },
                                                     new_values: { 'created_at' => 2 })])

            expect(data.first).to include('previousValues' => {}, 'newValues' => {})
          end

          # A read-only column is never captured, so the snapshot answers nil for it — `!=` would match and an
          # ordered operator would raise. Neither is an answer about the record that was deleted.
          it 'withholds when the scope asks about a column the snapshot never captured' do
            data = history_of([audit_entry('delete', previous_values: { 'status' => 'mine' })],
                              scope: Nodes::ConditionTreeLeaf.new('created_at', Operators::NOT_EQUAL, 'private'))

            expect(data.first['previousValues']).to eq({})
          end

          it 'withholds rather than comparing an ordered operator against a column it never captured' do
            data = history_of([audit_entry('delete', previous_values: { 'status' => 'mine' })],
                              scope: Nodes::ConditionTreeLeaf.new('created_at', Operators::LESS_THAN, 10))

            expect(data.first['previousValues']).to eq({})
          end

          # A placeholder is not the value the scope asked about.
          it 'withholds when the scoped column was captured redacted' do
            redacted = ForestAdminAgent::AuditTrail::Recording::REDACTED
            data = history_of([audit_entry('delete', previous_values: { 'status' => redacted })],
                              scope: Nodes::ConditionTreeLeaf.new('status', Operators::NOT_EQUAL, 'private'))

            expect(data.first['previousValues']).to eq({})
          end

          # An update that moved a writable primary key files its row under the id the record ended up with and
          # keeps the old one on `previous_record_id`. The snapshot answers for the key on both sides — unless
          # the trail redacts it, and then the id each side was filed under is the only thing left to answer
          # with. Taking the row's id for both sides would let the new state decide about the old one.
          describe 'an update that moved a redacted primary key' do
            def renamed_entry
              redacted = ForestAdminAgent::AuditTrail::Recording::REDACTED
              ForestAdminAgent::AuditTrail::AuditRecord.new(
                operation: 'update', collection: 'projects', record_id: '9', previous_record_id: '4',
                previous_values: { 'id' => redacted, 'status' => 'was theirs' },
                new_values: { 'id' => redacted, 'status' => 'now mine' }
              )
            end

            it 'withholds the previous side from a scope that only matches the id it moved to' do
              data = history_of([renamed_entry], scope: Nodes::ConditionTreeLeaf.new('id', Operators::EQUAL, 9))

              expect(data.first['previousValues']).to eq({})
              expect(data.first['newValues']).to include('status' => 'now mine')
            end

            it 'keeps the previous side for a scope that matches the id it moved from' do
              data = history_of([renamed_entry], scope: Nodes::ConditionTreeLeaf.new('id', Operators::EQUAL, 4))

              expect(data.first['previousValues']).to include('status' => 'was theirs')
              expect(data.first['newValues']).to eq({})
            end
          end

          # A pending row is filed under the id the record had before the write, so it cannot answer for the
          # state the update was moving to.
          it 'gives the new side of a pending update no id to fill from' do
            redacted = ForestAdminAgent::AuditTrail::Recording::REDACTED
            entry = ForestAdminAgent::AuditTrail::AuditRecord.new(
              operation: 'update', collection: 'projects', record_id: '4',
              status: ForestAdminAgent::AuditTrail::Recording::PENDING,
              previous_values: { 'id' => redacted, 'status' => 'was mine' },
              new_values: { 'id' => redacted, 'status' => 'now theirs' }
            )
            data = history_of([entry], scope: Nodes::ConditionTreeLeaf.new('id', Operators::EQUAL, 4))

            expect(data.first['previousValues']).to include('status' => 'was mine')
            expect(data.first['newValues']).to eq({})
          end

          # A captured nil holds its key, so the answerability test passes it through to an operator that
          # cannot compare it. Failing the whole page over one row would take the other rows with it.
          it 'withholds a row whose captured nil an ordered operator cannot compare' do
            data = history_of([audit_entry('delete', previous_values: { 'budget' => nil, 'status' => 'mine' })],
                              scope: Nodes::ConditionTreeLeaf.new('budget', Operators::GREATER_THAN, 1000))

            expect(data.first).to include('operation' => 'delete', 'previousValues' => {})
          end

          # An id written under an older schema stops decoding when the primary key changes arity.
          describe 'a row whose stored id no longer decodes' do
            def undecodable_entry
              ForestAdminAgent::AuditTrail::AuditRecord.new(
                operation: 'delete', collection: 'projects', record_id: '4|legacy',
                previous_values: { 'status' => 'mine' }, new_values: {}
              )
            end

            it 'withholds from a scope on the id rather than failing the page' do
              data = history_of([undecodable_entry], scope: Nodes::ConditionTreeLeaf.new('id', Operators::EQUAL, 4))

              expect(data.first).to include('operation' => 'delete', 'previousValues' => {})
            end

            # The id is all that could not be read. A scope that never asks about it is still answerable
            # from the columns the row captured.
            it 'still answers a scope that never asks about the id' do
              data = history_of([undecodable_entry],
                                scope: Nodes::ConditionTreeLeaf.new('status', Operators::EQUAL, 'mine'))

              expect(data.first['previousValues']).to eq({ 'status' => 'mine' })
            end

            it 'logs the id it could not read' do
              logger = instance_double(ForestAdminAgent::Services::LoggerService, log: nil)
              allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(logger)

              history_of([undecodable_entry], scope: Nodes::ConditionTreeLeaf.new('id', Operators::EQUAL, 4))

              expect(logger).to have_received(:log).with('Warn', a_string_including('id not decodable'))
            end
          end

          # The packed id fills in only what the snapshot cannot answer. A moved primary key the trail did
          # not redact is carried by both sides, so neither needs the row's own id, and letting it win would
          # judge the previous side by the id the record moved to.
          it 'lets a side that captured the key keep its own, over the id the row is filed under' do
            entry = ForestAdminAgent::AuditTrail::AuditRecord.new(
              operation: 'update', collection: 'projects', record_id: '9',
              previous_values: { 'id' => 4, 'status' => 'was theirs' },
              new_values: { 'id' => 9, 'status' => 'now mine' }
            )
            data = history_of([entry], scope: Nodes::ConditionTreeLeaf.new('id', Operators::EQUAL, 9))

            expect(data.first['previousValues']).to eq({})
            expect(data.first['newValues']).to eq({ 'id' => 9, 'status' => 'now mine' })
          end

          # A writable primary key the trail redacts is the one case where the two disagree: the placeholder
          # would read as unanswered, while the id the row is filed under proves what the key was.
          it 'reads a redacted primary key back from the packed id rather than the snapshot' do
            redacted = ForestAdminAgent::AuditTrail::Recording::REDACTED
            data = history_of([audit_entry('delete', previous_values: { 'id' => redacted, 'status' => 'mine' })],
                              scope: Nodes::ConditionTreeLeaf.new('id', Operators::EQUAL, 4))

            expect(data.first['previousValues']).to eq({ 'id' => redacted, 'status' => 'mine' })
          end

          # A read-only primary key never lands in the snapshot; the row's own packed id carries it.
          it 'matches a scope on the primary key through the row id' do
            entry = audit_entry('delete', previous_values: { 'status' => 'mine' })
            data = history_of([entry], scope: Nodes::ConditionTreeLeaf.new('id', Operators::EQUAL, 4))

            expect(data.first['previousValues']).to eq({ 'status' => 'mine' })
          end

          # A submitted form and a result summary, not column values.
          it 'leaves action rows untouched' do
            data = history_of([audit_entry('action', previous_values: { 'amount' => 12 })])

            expect(data.first['previousValues']).to eq({ 'amount' => 12 })
          end

          it 'leaves every value alone when no scope applies' do
            data = history_of([audit_entry('delete', previous_values: { 'status' => 'someone else' })], scope: nil)

            expect(data.first['previousValues']).to eq({ 'status' => 'someone else' })
          end
        end

        # The scope check runs before the store read, so the record can be deleted in between — and the rows
        # that come back then already carry its delete.
        it 'withholds a record deleted between the scope check and the store read' do
          allow(permissions).to receive(:get_scope)
            .and_return(Nodes::ConditionTreeLeaf.new('status', Operators::EQUAL, 'mine'))
          # Present and in scope when checked; gone, in scope and out, when asked again after the read.
          allow(collection).to receive(:list).and_return([{ 'id' => 4 }], [], [])
          entry = ForestAdminAgent::AuditTrail::AuditRecord.new(
            operation: 'delete', collection: 'projects', record_id: '4',
            previous_values: { 'status' => 'someone else' }, new_values: {}
          )
          route = route_with_store(records: [entry])

          result = route.handle_request({ headers: {}, params: { 'collection_name' => 'projects', 'id' => '4' } })

          expect(result[:content][:data].first).to include('operation' => 'delete', 'previousValues' => {})
        end

        it 'does not withhold anything when the record still exists in scope' do
          scope = Nodes::ConditionTreeLeaf.new('status', Operators::EQUAL, 'mine')
          allow(permissions).to receive(:get_scope).and_return(scope)
          entry = ForestAdminAgent::AuditTrail::AuditRecord.new(
            operation: 'delete', collection: 'projects', record_id: '4',
            previous_values: { 'status' => 'archived' }, new_values: {}
          )
          route = route_with_store(records: [entry])

          result = route.handle_request({ headers: {}, params: { 'collection_name' => 'projects', 'id' => '4' } })

          expect(result[:content][:data].first['previousValues']).to eq({ 'status' => 'archived' })
        end

        # Rows written before an update moved a writable primary key stay under the id they were true of, so
        # asking for the current id alone would start the story at the rename.
        describe 'a record that was renamed' do
          it 'reads the history of every id it has been filed under' do
            route = route_with_store
            allow(store).to receive(:renamed_from)
              .and_return([{ id: '1', until: '2026-01-02T00:00:05.000Z', until_row: 12 }], [])

            route.handle_request({ headers: {}, params: { 'collection_name' => 'projects', 'id' => '4' } })

            expected = [{ id: '4', until: nil, until_row: nil },
                        { id: '1', until: '2026-01-02T00:00:05.000Z', until_row: 12 }]
            expect(store).to have_received(:list_by_record).with(hash_including(record_id: expected))
            expect(store).to have_received(:count_by_record).with(hash_including(record_id: expected))
          end

          # Two hops means two real bounds to compare, which is the path a single rename never reaches.
          it 'carries the earlier bound down a chain of two renames' do
            route = route_with_store
            allow(store).to receive(:renamed_from).and_return(
              [{ id: '7', until: '2026-01-02T00:00:09.000Z', until_row: 20 }],
              [{ id: '1', until: '2026-01-02T00:00:05.000Z', until_row: 10 }],
              []
            )

            route.handle_request({ headers: {}, params: { 'collection_name' => 'projects', 'id' => '9' } })

            expect(store).to have_received(:list_by_record).with(
              hash_including(record_id: [
                               { id: '9', until: nil, until_row: nil },
                               { id: '7', until: '2026-01-02T00:00:09.000Z', until_row: 20 },
                               { id: '1', until: '2026-01-02T00:00:05.000Z', until_row: 10 }
                             ])
            )
          end

          # The middle id was left later than the one before it, so the older segment keeps its own, earlier
          # bound rather than inheriting the looser one.
          it 'keeps the earlier of the two bounds when the chain reports a later one' do
            route = route_with_store
            allow(store).to receive(:renamed_from).and_return(
              [{ id: '7', until: '2026-01-02T00:00:05.000Z', until_row: 10 }],
              [{ id: '1', until: '2026-01-02T00:00:09.000Z', until_row: 20 }],
              []
            )

            route.handle_request({ headers: {}, params: { 'collection_name' => 'projects', 'id' => '9' } })

            expect(store).to have_received(:list_by_record).with(
              hash_including(record_id: [
                               { id: '9', until: nil, until_row: nil },
                               { id: '7', until: '2026-01-02T00:00:05.000Z', until_row: 10 },
                               { id: '1', until: '2026-01-02T00:00:05.000Z', until_row: 10 }
                             ])
            )
          end

          it 'stops walking rather than looping on a chain that comes back to itself' do
            route = route_with_store
            allow(store).to receive(:renamed_from).and_return(
              [{ id: '1', until: nil, until_row: nil }], [{ id: '4', until: nil, until_row: nil }]
            )

            route.handle_request({ headers: {}, params: { 'collection_name' => 'projects', 'id' => '4' } })

            expect(store).to have_received(:list_by_record).with(
              hash_including(record_id: [{ id: '4', until: nil, until_row: nil },
                                         { id: '1', until: nil, until_row: nil }])
            )
          end
        end

        describe 'meta.availableUsers' do
          let(:authors) do
            [{ user_id: 12, user_first_name: 'Ada', user_last_name: 'L', user_email: 'ada@test' }]
          end

          # The distinct authors of what the filters match, whatever page was asked for, in the shape the
          # filter dropdown wants.
          it 'lists the authors of the matching entries on the first fetch' do
            route = route_with_store
            allow(store).to receive(:authors_by_record).and_return(authors)

            result = route.handle_request({ headers: {}, params: { 'collection_name' => 'projects', 'id' => '4' } })

            expect(result[:content][:meta][:availableUsers]).to eq(
              [{ id: 12, firstName: 'Ada', lastName: 'L', email: 'ada@test' }]
            )
            expect(store).to have_received(:authors_by_record)
              .with(collection: 'projects', record_id: [{ id: '4', until: nil, until_row: nil }])
          end

          # The front keeps the list it saw, so later pages leave it out.
          it 'leaves it out past the first page, and does not even ask for it' do
            route = route_with_store
            allow(store).to receive(:authors_by_record).and_return(authors)

            result = route.handle_request(
              { headers: {},
                params: { 'collection_name' => 'projects', 'id' => '4', 'page' => { 'number' => '2' } } }
            )

            expect(result[:content][:meta]).to eq({ count: 0 })
            expect(store).not_to have_received(:authors_by_record)
          end

          it 'answers the active filters, not the whole history' do
            route = route_with_store
            allow(store).to receive(:authors_by_record).and_return(authors)

            route.handle_request({ headers: {},
                                   params: { 'collection_name' => 'projects', 'id' => '4', 'userIds' => '12' } })

            expect(store).to have_received(:authors_by_record).with(hash_including(user_ids: [12]))
          end
        end

        it 'defaults to newest-first and switches to oldest-first on sort=timestamp' do
          route = route_with_store
          route.handle_request({ headers: {}, params: { 'collection_name' => 'projects', 'id' => '4', 'sort' => 'timestamp' } })

          expect(store).to have_received(:list_by_record).with(hash_including(order: 'asc'))
        end

        it 'caps page[size] at 100 and honors page[number]' do
          route = route_with_store
          route.handle_request({ headers: {},
                                 params: { 'collection_name' => 'projects', 'id' => '4',
                                           'page' => { 'size' => '500', 'number' => '3' } } })

          expect(store).to have_received(:list_by_record).with(hash_including(skip: 200, limit: 100))
        end

        it 'falls back to the default page when page is not a hash' do
          route = route_with_store
          route.handle_request({ headers: {}, params: { 'collection_name' => 'projects', 'id' => '4', 'page' => 'foo' } })

          expect(store).to have_received(:list_by_record).with(hash_including(skip: 0, limit: 20))
        end

        it 'passes a search term through, trimmed' do
          route = route_with_store
          route.handle_request({ headers: {},
                                 params: { 'collection_name' => 'projects', 'id' => '4',
                                           'search' => '  Lyon  ' } })

          expect(store).to have_received(:list_by_record).with(hash_including(search: 'Lyon'))
          # The count has to agree with the filter, like every other one.
          expect(store).to have_received(:count_by_record).with(hash_including(search: 'Lyon'))
        end

        it 'sends no search when the term is blank' do
          route = route_with_store
          route.handle_request({ headers: {},
                                 params: { 'collection_name' => 'projects', 'id' => '4', 'search' => '   ' } })

          expect(store).to have_received(:list_by_record).with(hash_excluding(:search))
        end

        it 'combines a search with the other filters as one AND' do
          route = route_with_store
          route.handle_request({ headers: {},
                                 params: { 'collection_name' => 'projects', 'id' => '4', 'search' => 'Lyon',
                                           'userIds' => '12', 'fields' => 'address.city' } })

          expect(store).to have_received(:list_by_record).with(
            hash_including(search: 'Lyon', user_ids: [12], fields: ['address.city'])
          )
        end

        it 'passes a fields filter through, keeping names that hold a dot' do
          route = route_with_store
          route.handle_request({ headers: {},
                                 params: { 'collection_name' => 'projects', 'id' => '4',
                                           'fields' => 'status, address.city ,' } })

          expect(store).to have_received(:list_by_record).with(hash_including(fields: ['status', 'address.city']))
          expect(store).to have_received(:count_by_record).with(hash_including(fields: ['status', 'address.city']))
        end

        it 'sends no fields filter when the param is absent or empty' do
          route = route_with_store
          route.handle_request({ headers: {},
                                 params: { 'collection_name' => 'projects', 'id' => '4', 'fields' => ' , ' } })

          expect(store).to have_received(:list_by_record).with(hash_excluding(:fields))
        end

        it 'parses userIds, dropping non-numeric tokens' do
          route = route_with_store
          route.handle_request({ headers: {},
                                 params: { 'collection_name' => 'projects', 'id' => '4', 'userIds' => '7, x ,9' } })

          expect(store).to have_received(:list_by_record).with(hash_including(user_ids: [7, 9]))
        end

        it 'parses a date range into inclusive UTC boundaries' do
          route = route_with_store
          route.handle_request({ headers: {},
                                 params: { 'collection_name' => 'projects', 'id' => '4',
                                           'startDate' => '2026-01-02', 'endDate' => '2026-01-02' } })

          expect(store).to have_received(:list_by_record).with(
            hash_including(start_timestamp: '2026-01-02T00:00:00.000Z',
                           end_timestamp: '2026-01-02T23:59:59.999Z')
          )
        end

        it 'reads dates as local time in the request timezone' do
          route = route_with_store
          route.handle_request({ headers: {},
                                 params: { 'collection_name' => 'projects', 'id' => '4',
                                           'timezone' => 'America/New_York', 'startDate' => '2026-01-02' } })

          # 2026-01-02 00:00 in New York (UTC-5) is 05:00 UTC.
          expect(store).to have_received(:list_by_record).with(hash_including(start_timestamp: '2026-01-02T05:00:00.000Z'))
        end

        it 'reads a wall-clock datetime, completing a minutes-only end boundary to :59.999' do
          route = route_with_store
          route.handle_request({ headers: {},
                                 params: { 'collection_name' => 'projects', 'id' => '4',
                                           'startDate' => '2026-01-02T08:30', 'endDate' => '2026-01-02 09:30' } })

          expect(store).to have_received(:list_by_record).with(
            hash_including(start_timestamp: '2026-01-02T08:30:00.000Z',
                           end_timestamp: '2026-01-02T09:30:59.999Z')
          )
        end

        it 'keeps explicit seconds as given on both bounds' do
          route = route_with_store
          route.handle_request({ headers: {},
                                 params: { 'collection_name' => 'projects', 'id' => '4',
                                           'startDate' => '2026-01-02T08:30:15',
                                           'endDate' => '2026-01-02T09:30:45' } })

          expect(store).to have_received(:list_by_record).with(
            hash_including(start_timestamp: '2026-01-02T08:30:15.000Z',
                           end_timestamp: '2026-01-02T09:30:45.000Z')
          )
        end

        # Right shape, impossible instant: the regex accepts it, the zone refuses to parse it.
        it 'rejects a well-formed datetime that is out of range' do
          route = route_with_store

          expect do
            route.handle_request({ headers: {},
                                   params: { 'collection_name' => 'projects', 'id' => '4',
                                             'startDate' => '2026-01-02T99:00' } })
          end.to raise_error(Http::Exceptions::ValidationError, /Invalid date/)
        end

        it 'rejects an unparsable date' do
          route = route_with_store

          expect do
            route.handle_request({ headers: {},
                                   params: { 'collection_name' => 'projects', 'id' => '4', 'startDate' => 'nope' } })
          end.to raise_error(Http::Exceptions::ValidationError, /Invalid date/)
        end

        it 'rejects an unknown timezone' do
          route = route_with_store

          expect do
            route.handle_request({ headers: {},
                                   params: { 'collection_name' => 'projects', 'id' => '4',
                                             'timezone' => 'Mars/Phobos', 'startDate' => '2026-01-02' } })
          end.to raise_error(Http::Exceptions::ValidationError, /Invalid timezone/)
        end
      end
    end
  end
end
