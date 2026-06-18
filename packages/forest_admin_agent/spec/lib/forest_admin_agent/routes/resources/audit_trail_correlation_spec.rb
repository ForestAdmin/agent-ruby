require 'spec_helper'

module ForestAdminAgent
  module Routes
    module Resources
      describe AuditTrailCorrelation do
        let(:store) { double('store') }
        let(:collection) { double('collection', name: 'books') }

        def route_with_store(history: [])
          allow(ForestAdminAgent::Facades::Container).to receive(:config_from_cache)
            .and_return({ audit_trail: { store: store } })
          allow(store).to receive_messages(list_by_correlation: history, list_by_correlations: history)

          route = described_class.new
          datasource = double('datasource')
          allow(datasource).to receive(:get_collection).with('books').and_return(collection)
          context = double('context', datasource: datasource,
                                      permissions: double('permissions', can?: true))
          allow(route).to receive(:build).and_return(context)
          route
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
          route = route_with_store(history: [double('entry', to_h: { operation: 'update' })])

          result = route.handle_history(
            { headers: {}, params: { 'collection' => 'books', 'recordId' => '2', 'correlation_key' => 'req-1' } }
          )

          expect(store).to have_received(:list_by_correlation).with(
            collection: 'books', record_id: '2', correlation_key: 'req-1'
          )
          expect(result[:content]).to eq({ data: [{ operation: 'update' }] })
        end

        it 'reads a batch history from comma-separated query keys (GET)' do
          route = route_with_store(history: [double('entry', to_h: { operation: 'update' })])

          route.handle_batch(
            { headers: {}, params: { 'collection' => 'books', 'recordId' => '2', 'correlationKeys' => 'a, b' } }
          )

          expect(store).to have_received(:list_by_correlations).with(
            collection: 'books', record_id: '2', correlation_keys: %w[a b]
          )
        end

        it 'reads a batch history from a body array (POST)' do
          route = route_with_store

          route.handle_batch(
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
