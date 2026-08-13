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
                )
              }
            },
            list: [{ 'id' => 4 }]
          )
        end

        def route_with_store(records: [])
          allow(ForestAdminAgent::Facades::Container).to receive(:config_from_cache)
            .and_return({ audit_trail: { store: store } })
          allow(store).to receive_messages(list_by_record: records, count_by_record: records.length)

          route = described_class.new
          context = double('context', collection: collection, caller: build_caller, permissions: permissions)
          allow(route).to receive(:build).and_return(context)
          route
        end

        describe 'state reconstruction' do
          def state_route(entries: [], record: { 'id' => 4, 'status' => 'shipped' })
            allow(ForestAdminAgent::Facades::Container).to receive(:config_from_cache)
              .and_return({ audit_trail: { store: store } })
            allow(store).to receive(:list_since).and_return(entries)
            allow(collection).to receive(:list).and_return([{ 'id' => 4 }], [record].compact)

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

          def get_state(route, timestamp: '2026-01-02T10:00:00.000Z', extra: {})
            route.handle_state(
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

            expect(result[:content][:data]).to eq({ 'id' => 4, 'status' => 'paid' })
            expect(result[:content][:meta]).to eq({ timestamp: '2026-01-02T10:00:00.000Z', reverted: 1 })
          end

          # Strictly after the requested instant: an entry stamped exactly at it belongs to that state.
          it 'asks the store for entries strictly newer than the instant' do
            route = state_route
            get_state(route)

            expect(store).to have_received(:list_since).with(
              collection: 'projects', record_id: '4', timestamp: '2026-01-02T10:00:00.000Z'
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
            collection: 'projects', record_id: '4', skip: 0, limit: 20, order: 'desc'
          )
          expect(store).to have_received(:count_by_record).with(collection: 'projects', record_id: '4')
          # Top-level keys are camelCased for the frontend; nested value hashes keep the column names.
          expect(result[:content]).to eq(
            {
              data: [{ 'operation' => 'update', 'recordId' => '4', 'previousValues' => { 'first_name' => 'Jo' } }],
              meta: { count: 1 }
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
