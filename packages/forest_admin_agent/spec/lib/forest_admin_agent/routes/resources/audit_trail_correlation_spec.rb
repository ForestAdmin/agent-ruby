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
                ),
                'title' => ColumnSchema.new(column_type: 'String')
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

        # These routes serve the same rows as the per-record history route, so what that route withholds must
        # not come back through a correlation lookup.
        describe 'a gone record whose captured values fall outside the caller scope' do
          def audit_entry(previous_values)
            ForestAdminAgent::AuditTrail::AuditRecord.new(
              operation: 'delete', collection: 'books', record_id: '2', previous_values: previous_values
            )
          end

          def gone_record(scope: Nodes::ConditionTreeLeaf.new('title', Operators::EQUAL, 'mine'))
            allow(permissions).to receive(:get_scope).and_return(scope)
            # Empty in scope and empty without it: the record is gone for good.
            allow(collection).to receive(:list).and_return([])
          end

          def history_params
            { headers: {}, params: { 'collection' => 'books', 'recordId' => '2', 'correlation_key' => 'req-1' } }
          end

          it 'withholds the values of a row that fails the scope, keeping the row itself' do
            gone_record
            route = route_with_store(history: [audit_entry({ 'title' => 'someone else' })])

            data = route.handle_history(history_params).dig(:content, :data)

            expect(data.first).to include('operation' => 'delete', 'recordId' => '2', 'previousValues' => {})
          end

          it 'keeps the values of a row that passes the scope' do
            gone_record
            route = route_with_store(history: [audit_entry({ 'title' => 'mine' })])

            data = route.handle_history(history_params).dig(:content, :data)

            expect(data.first['previousValues']).to eq({ 'title' => 'mine' })
          end

          it 'withholds on the batch route too' do
            gone_record
            route = route_with_store(history: [audit_entry({ 'title' => 'someone else' })])

            data = route.handle_batch(
              { headers: {}, params: { 'collection' => 'books', 'recordId' => '2', 'correlationKeys' => 'a' } }
            ).dig(:content, :data)

            expect(data.first['previousValues']).to eq({})
          end

          # The check that authorized the request ran before these rows were read, so it is asked again.
          it 'withholds rows whose record was deleted after the request was authorized' do
            allow(permissions).to receive(:get_scope).and_return(Nodes::ConditionTreeLeaf.new('title',
                                                                                              Operators::EQUAL,
                                                                                              'mine'))
            # In scope on the way in, gone by the time the rows are in hand.
            allow(collection).to receive(:list).and_return([{ 'id' => 2 }], [], [])
            route = route_with_store(history: [audit_entry({ 'title' => 'someone else' })])

            data = route.handle_history(history_params).dig(:content, :data)

            expect(data.first['previousValues']).to eq({})
          end

          it 'answers 404 when the record moved out of the caller scope while the rows were being read' do
            allow(permissions).to receive(:get_scope).and_return(Nodes::ConditionTreeLeaf.new('title',
                                                                                              Operators::EQUAL,
                                                                                              'mine'))
            # In scope on the way in, someone else's by the time the rows are in hand.
            allow(collection).to receive(:list).and_return([{ 'id' => 2 }], [], [{ 'id' => 2 }])
            route = route_with_store(history: [audit_entry({ 'title' => 'mine' })])

            expect { route.handle_history(history_params) }.to raise_error(Http::Exceptions::NotFoundError)
          end

          # A replacement answers for itself: these rows belong to the record that held the id before it.
          it 'keeps withholding when an in-scope record has taken the id since' do
            allow(permissions).to receive(:get_scope).and_return(Nodes::ConditionTreeLeaf.new('title',
                                                                                              Operators::EQUAL,
                                                                                              'mine'))
            # Gone on the way in, in scope and without it; a record of the caller's own under that id after.
            allow(collection).to receive(:list).and_return([], [], [{ 'id' => 2, 'title' => 'mine' }])
            route = route_with_store(history: [audit_entry({ 'title' => 'someone else' })])

            data = route.handle_history(history_params).dig(:content, :data)

            expect(data.first).to include('operation' => 'delete', 'previousValues' => {})
          end

          # Gone when the request was authorized, somebody else's by the time the rows came back. The first
          # check cannot stand in for the second, or this route answers what a request starting a moment
          # later would refuse.
          it 'answers 404 when the id was taken by an out-of-scope record while the rows were being read' do
            allow(permissions).to receive(:get_scope).and_return(Nodes::ConditionTreeLeaf.new('title',
                                                                                              Operators::EQUAL,
                                                                                              'mine'))
            # Gone on the way in, in scope and without it; someone else's by the time the rows are in hand.
            allow(collection).to receive(:list).and_return([], [], [], [{ 'id' => 2 }])
            route = route_with_store(history: [audit_entry({ 'title' => 'mine' })])

            expect { route.handle_history(history_params) }.to raise_error(Http::Exceptions::NotFoundError)
          end

          # An empty answer has nothing to withhold, so it does not earn a second read of the record.
          it 'does not read the record again when the history is empty' do
            allow(permissions).to receive(:get_scope).and_return(Nodes::ConditionTreeLeaf.new('title',
                                                                                              Operators::EQUAL,
                                                                                              'mine'))
            allow(collection).to receive(:list).and_return([{ 'id' => 2 }])
            route = route_with_store(history: [])

            route.handle_history(history_params)

            expect(collection).to have_received(:list).once
          end
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
