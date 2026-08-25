require 'spec_helper'

module ForestAdminAgent
  module Routes
    module Resources
      include ForestAdminDatasourceToolkit::Schema
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

      describe AuditTrailCorrelation do
        let(:store) { double('store') }
        let(:permissions) { double('permissions', can?: true, get_scope: nil) }
        let(:collection) do
          build_collection(
            name: 'books',
            schema: {
              fields: {
                'id' => ColumnSchema.new(
                  column_type: 'Number', is_primary_key: true,
                  filter_operators: [Operators::IN, Operators::EQUAL]
                )
              }
            },
            list: [{ 'id' => 2 }]
          )
        end

        def route_with_store(history: [])
          allow(ForestAdminAgent::Facades::Container).to receive(:config_from_cache)
            .and_return({ audit_trail: { store: store } })
          allow(store).to receive_messages(list_by_correlation: history, list_by_correlations: history)

          route = described_class.new
          datasource = double('datasource')
          allow(datasource).to receive(:get_collection).with('books').and_return(collection)
          context = double('context', datasource: datasource, caller: build_caller, permissions: permissions)
          allow(route).to receive(:build).and_return(context)
          route
        end

        it 'returns 404 without touching the store when the record exists outside the caller scope' do
          allow(permissions).to receive(:get_scope).and_return(Nodes::ConditionTreeLeaf.new('id', Operators::EQUAL, 9))
          allow(collection).to receive(:list).and_return([], [{ 'id' => 2 }])
          route = route_with_store

          expect do
            route.handle_history(
              { headers: {}, params: { 'collection' => 'books', 'recordId' => '2', 'correlation_key' => 'req-1' } }
            )
          end.to raise_error(Http::Exceptions::NotFoundError)

          expect(store).not_to have_received(:list_by_correlation)
        end

        it 'registers the correlation routes when a store is configured' do
          allow(ForestAdminAgent::Facades::Container).to receive(:config_from_cache)
            .and_return({ audit_trail: { store: Object.new } })

          expect(described_class.new.routes.keys).to include(
            'forest_audit_trail_correlation', 'forest_audit_trail_correlations', 'forest_audit_trail_correlations_batch'
          )
        end

        it 'does not register when no store is configured' do
          allow(ForestAdminAgent::Facades::Container).to receive(:config_from_cache).and_return({})

          expect(described_class.new.routes).to be_empty
        end

        it 'reads a single correlation history scoped to the record' do
          entry = { operation: 'update', record_id: '2', new_values: { 'first_name' => 'Jo' } }
          route = route_with_store(history: [double('entry', to_h: entry)])

          # Through the registered closure rather than the handler, so the wiring is covered too.
          result = route.routes['forest_audit_trail_correlation'][:closure].call(
            { headers: {}, params: { 'collection' => 'books', 'recordId' => '2', 'correlation_key' => 'req-1' } }
          )

          expect(store).to have_received(:list_by_correlation).with(
            collection: 'books', record_id: '2', correlation_key: 'req-1'
          )
          # Same serialization as the per-record route: camelCase on top, column names left alone.
          expect(result[:content]).to eq(
            { data: [{ 'operation' => 'update', 'recordId' => '2', 'newValues' => { 'first_name' => 'Jo' } }] }
          )
        end

        it 'reads a batch history from comma-separated query keys (GET)' do
          route = route_with_store(history: [double('entry', to_h: { operation: 'update' })])

          route.routes['forest_audit_trail_correlations'][:closure].call(
            { headers: {}, params: { 'collection' => 'books', 'recordId' => '2', 'correlationKeys' => 'a, b' } }
          )

          expect(store).to have_received(:list_by_correlations).with(
            collection: 'books', record_id: '2', correlation_keys: %w[a b]
          )
        end

        it 'reads a batch history from a body array (POST)' do
          route = route_with_store

          route.routes['forest_audit_trail_correlations_batch'][:closure].call(
            { headers: {}, params: { 'collection' => 'books', 'recordId' => '2', 'correlationKeys' => %w[a b] } }
          )

          expect(store).to have_received(:list_by_correlations).with(
            collection: 'books', record_id: '2', correlation_keys: %w[a b]
          )
        end

        it 'returns an empty batch without hitting the store when no keys are given' do
          route = route_with_store

          result = route.handle_batch({ headers: {}, params: { 'collection' => 'books', 'recordId' => '2' } })

          expect(store).not_to have_received(:list_by_correlations)
          expect(result[:content]).to eq({ data: [] })
        end

        it 'answers 404 for a collection the datasource does not know' do
          route = route_with_store
          datasource = double('datasource')
          allow(datasource).to receive(:get_collection).with('ghosts')
                                                       .and_raise(ForestAdminDatasourceToolkit::Exceptions::ForestException,
                                                                  "Collection 'ghosts' not found")
          allow(route).to receive(:build).and_return(
            double('context', datasource: datasource, caller: build_caller, permissions: permissions)
          )

          expect do
            route.handle_history(
              { headers: {}, params: { 'collection' => 'ghosts', 'recordId' => '2', 'correlation_key' => 'req-1' } }
            )
          end.to raise_error(Http::Exceptions::NotFoundError, /not found/)
        end

        it 'passes through a datasource error that is not a missing collection' do
          route = route_with_store
          datasource = double('datasource')
          allow(datasource).to receive(:get_collection).with('books')
                                                       .and_raise(ForestAdminDatasourceToolkit::Exceptions::ForestException,
                                                                  'connection lost')
          allow(route).to receive(:build).and_return(
            double('context', datasource: datasource, caller: build_caller, permissions: permissions)
          )

          expect do
            route.handle_history(
              { headers: {}, params: { 'collection' => 'books', 'recordId' => '2', 'correlation_key' => 'req-1' } }
            )
          end.to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException, /connection lost/)
        end

        it 'rejects a missing collection' do
          route = route_with_store

          expect do
            route.handle_history({ headers: {}, params: { 'recordId' => '2', 'correlation_key' => 'req-1' } })
          end.to raise_error(Http::Exceptions::ValidationError, /Missing collection/)
        end

        it 'rejects a missing recordId' do
          route = route_with_store

          expect do
            route.handle_history({ headers: {}, params: { 'collection' => 'books', 'correlation_key' => 'req-1' } })
          end.to raise_error(Http::Exceptions::ValidationError, /Missing recordId/)
        end
      end
    end
  end
end
