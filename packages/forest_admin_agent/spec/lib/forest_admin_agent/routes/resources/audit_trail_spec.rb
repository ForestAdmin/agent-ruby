require 'spec_helper'

module ForestAdminAgent
  module Routes
    module Resources
      describe AuditTrail do
        let(:store) { double('store') }

        def route_with_store(records: [])
          allow(ForestAdminAgent::Facades::Container).to receive(:config_from_cache)
            .and_return({ audit_trail: { store: store } })
          allow(store).to receive_messages(list_by_record: records, count_by_record: records.length)

          route = described_class.new
          context = double('context', collection: double('collection', name: 'projects'),
                                      permissions: double('permissions', can?: true))
          allow(route).to receive(:build).and_return(context)
          route
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

          result = route.handle_request({ headers: {}, params: { 'collection_name' => 'projects', 'id' => '4' } })

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
