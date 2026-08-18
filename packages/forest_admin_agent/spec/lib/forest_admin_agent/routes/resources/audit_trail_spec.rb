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
                'status' => ColumnSchema.new(column_type: 'String')
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
          # back a row the check never covered.
          it 'reads the record through the caller scope, in a single query' do
            scope = Nodes::ConditionTreeLeaf.new('id', Operators::EQUAL, 4)
            allow(permissions).to receive(:get_scope).and_return(scope)
            route = state_route

            get_state(route)

            expect(collection).to have_received(:list).once
            expect(collection).to have_received(:list) do |_caller, filter, projection|
              expect(filter.condition_tree.conditions).to include(scope)
              expect(projection).to include('status')
            end
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

          expect(collection).to have_received(:list) do |_caller, filter, _projection|
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
          route = route_with_store(records: [double('entry', to_h: { operation: 'delete', record_id: '4' })])

          result = route.handle_request({ headers: {}, params: { 'collection_name' => 'projects', 'id' => '4' } })

          expect(result[:content][:data]).to eq([{ 'operation' => 'delete', 'recordId' => '4' }])
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
