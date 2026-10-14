require 'spec_helper'

module ForestAdminAgent
  module Routes
    module Resources
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

      describe AuditTrailTimeline do
        let(:store) { double('store') }
        let(:projects) { build_collection(name: 'projects') }
        let(:staff) { build_collection(name: 'staff') }
        let(:scoped) { build_collection(name: 'scoped') }
        let(:permissions) { double('permissions') }

        def row(id, timestamp)
          ForestAdminAgent::AuditTrail::AuditRecord.new(
            id: id, timestamp: timestamp, operation: 'update', collection: 'projects', record_id: '4',
            previous_values: { 'status' => 'open' }, new_values: { 'status' => 'closed' }
          )
        end

        def route_with(rows: [], authors: [])
          allow(ForestAdminAgent::Facades::Container).to receive(:config_from_cache)
            .and_return({ audit_trail: { store: store } })
          allow(store).to receive_messages(list_timeline: rows, timeline_users: authors)
          allow(permissions).to receive(:allowed_collections) { |_action, collections| collections - [staff] }
          allow(permissions).to receive(:get_scope) do |collection|
            collection == scoped ? Nodes::ConditionTreeLeaf.new('id', Operators::EQUAL, 1) : nil
          end

          route = described_class.new
          datasource = double('datasource', collections: { 'projects' => projects, 'staff' => staff,
                                                           'scoped' => scoped })
          context = double('context', datasource: datasource, caller: build_caller, permissions: permissions)
          allow(route).to receive(:build).and_return(context)
          route
        end

        def get(route, params = {})
          route.handle_request({ headers: {}, params: params })
        end

        it 'mounts GET /_audit-trail once a store is configured' do
          allow(ForestAdminAgent::Facades::Container).to receive(:config_from_cache)
            .and_return({ audit_trail: { store: store } })

          expect(described_class.new.routes['forest_audit_trail_timeline']).to include(method: 'get', uri: '/_audit-trail')
        end

        it 'is not mounted without a store' do
          allow(ForestAdminAgent::Facades::Container).to receive(:config_from_cache).and_return({})

          expect(described_class.new.routes).to be_empty
        end

        it 'reads only the readable collections without a record-level scope' do
          route = route_with

          get(route)

          expect(store).to have_received(:list_timeline).with(hash_including(collections: ['projects']))
        end

        it 'serves the values, camelCased like the per-record history' do
          route = route_with(rows: [row(1, '2026-01-02T03:04:05.000Z')])

          data = get(route)[:content][:data]

          expect(data.first).to include('id' => 1, 'recordId' => '4', 'newValues' => { 'status' => 'closed' })
        end

        it 'passes the filters, newest first by default, and never a fields filter' do
          route = route_with

          get(route, 'operations' => 'update', 'userIds' => '7', 'search' => ' Lyon ', 'fields' => 'status')

          expect(store).to have_received(:list_timeline).with(
            hash_including(order: 'desc', operations: ['update'], user_ids: [7], search: 'Lyon', limit: 21)
          )
          expect(store).to have_received(:list_timeline).with(hash_excluding(:fields))
        end

        it 'rejects an unknown operation' do
          route = route_with

          expect { get(route, 'operations' => 'rename') }.to raise_error(Http::Exceptions::ValidationError)
        end

        describe 'the cursor' do
          it 'is null on the last page' do
            route = route_with(rows: [row(1, '2026-01-02T03:04:05.000Z')])

            expect(get(route)[:content][:meta][:cursor]).to be_nil
          end

          it 'points before the last row newest first, excluding the rows tied with it' do
            rows = [row(3, '2026-01-02T03:04:06.000Z'), row(2, '2026-01-02T03:04:05.000Z'),
                    row(1, '2026-01-02T03:04:05.000Z')]
            route = route_with(rows: rows)

            meta = get(route, 'page' => { 'size' => '2' })[:content][:meta]

            expect(meta[:cursor]).to eq(before: '2026-01-02T03:04:05.000Z', excludeIds: [2])
          end

          it 'points after the last row oldest first, reading only the after bound' do
            rows = [row(1, '2026-01-02T03:04:05.000Z'), row(2, '2026-01-02T03:04:06.000Z'),
                    row(3, '2026-01-02T03:04:07.000Z')]
            route = route_with(rows: rows)

            meta = get(route, 'sort' => 'timestamp', 'page' => { 'size' => '2' },
                              'after' => '2026-01-02T03:04:00+00:00', 'before' => 'ignored')[:content][:meta]

            expect(store).to have_received(:list_timeline).with(
              hash_including(order: 'asc', after: '2026-01-02T03:04:00.000Z')
            )
            expect(store).to have_received(:list_timeline).with(hash_excluding(:before))
            expect(meta[:cursor]).to eq(after: '2026-01-02T03:04:06.000Z', excludeIds: [2])
          end

          it 'carries the previous exclusions while a tie spans several pages' do
            rows = [row(5, '2026-01-02T03:04:05.000Z'), row(4, '2026-01-02T03:04:05.000Z'),
                    row(3, '2026-01-02T03:04:05.000Z')]
            route = route_with(rows: rows)

            meta = get(route, 'before' => '2026-01-02T03:04:05.000Z', 'excludeIds' => '7,6',
                              'page' => { 'size' => '2' })[:content][:meta]

            expect(store).to have_received(:list_timeline).with(hash_including(exclude_ids: [7, 6]))
            expect(meta[:cursor]).to eq(before: '2026-01-02T03:04:05.000Z', excludeIds: [7, 6, 5, 4])
          end

          it 'ends the walk rather than loop when a page adds no exclusion on the same timestamp' do
            rows = [row(7, '2026-01-02T03:04:05.000Z'), row(6, '2026-01-02T03:04:05.000Z')]
            route = route_with(rows: rows)

            meta = get(route, 'before' => '2026-01-02T03:04:05.000Z', 'excludeIds' => '7',
                              'page' => { 'size' => '1' })[:content][:meta]

            expect(meta[:cursor]).to be_nil
          end

          it 'rejects a bound that is not an ISO instant' do
            route = route_with

            expect { get(route, 'before' => 'yesterday') }.to raise_error(Http::Exceptions::ValidationError)
          end
        end

        describe 'meta.availableUsers' do
          let(:authors) { [{ user_id: 7, user_first_name: 'Jane', user_last_name: 'Doe', user_email: 'j@d.io' }] }

          it 'lists the authors on the first page, under the same filters' do
            route = route_with(authors: authors)

            meta = get(route, 'userIds' => '7')[:content][:meta]

            expect(meta[:availableUsers]).to eq([{ id: 7, firstName: 'Jane', lastName: 'Doe', email: 'j@d.io' }])
            expect(store).to have_received(:timeline_users).with(hash_including(user_ids: [7], collections: ['projects']))
          end

          it 'omits the key on a later page' do
            route = route_with(authors: authors)

            meta = get(route, 'before' => '2026-01-02T03:04:05.000Z')[:content][:meta]

            expect(meta).not_to have_key(:availableUsers)
            expect(store).not_to have_received(:timeline_users)
          end
        end
      end
    end
  end
end
