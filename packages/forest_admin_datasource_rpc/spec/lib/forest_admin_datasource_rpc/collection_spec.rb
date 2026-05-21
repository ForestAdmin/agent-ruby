require 'spec_helper'
require 'shared/schema'
require 'logger'

module ForestAdminDatasourceRpc
  include ForestAdminDatasourceToolkit::Components::Query
  include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

  describe Collection do
    before do
      logger = instance_double(Logger, log: nil)
      allow(ForestAdminAgent::Facades::Container).to receive_messages(logger: logger, cache: 'secret')
      allow(Utils::RpcClient).to receive(:new).and_return(rpc_client)
    end

    let(:rpc_client) { instance_double(Utils::RpcClient, call_rpc: {}) }
    let(:datasource) { Datasource.new({ uri: 'http://localhost' }, introspection) }
    let(:collection) { datasource.get_collection('Product') }
    let(:caller) { build_caller }

    include_context 'with introspection'

    context 'when initialized' do
      it 'uses the datasource shared RPC client' do
        expect(collection.instance_variable_get(:@client)).to eq(datasource.shared_rpc_client)
      end

      context 'when the schema carries action static_form values' do
        let(:actions_introspection) do
          {
            charts: [],
            rpc_relations: [],
            collections: [
              {
                name: 'Files',
                countable: false,
                searchable: false,
                charts: [],
                segments: [],
                fields: {
                  id: {
                    column_type: 'Number', filter_operators: [], is_primary_key: true,
                    is_read_only: false, is_sortable: true, default_value: nil,
                    enum_values: [], validation: [], type: 'Column'
                  }
                },
                actions: {
                  'static_action': { scope: 'global', static_form: true },
                  'dynamic_action': { scope: 'global', static_form: false }
                }
              }
            ]
          }
        end
        let(:actions_datasource) { Datasource.new({ uri: 'http://localhost' }, actions_introspection) }

        it 'preserves :static_form from the wire instead of recomputing it against an empty form' do
          schema = actions_datasource.get_collection('Files').schema[:actions]
          expect(schema['static_action'].static_form).to be(true)
          expect(schema['dynamic_action'].static_form).to be(false)
        end
      end
    end

    context 'when call list' do
      it 'forward the call to the server' do
        collection.list(caller, Filter.new, Projection.new)

        expect(rpc_client).to have_received(:call_rpc) do |url, options|
          expect(url).to eq('/forest/rpc/Product/list')
          expect(options[:caller]).to eq(caller)
          expect(options[:method]).to eq(:post)
          expect(options[:payload]).to eq(
            {
              collection_name: 'Product',
              filter: Filter.new.to_h,
              projection: []
            }
          )
        end
      end

      it 'forward the call to the server with filter and projection' do
        filter = Filter.new(
          condition_tree: Nodes::ConditionTreeBranch.new(
            'And',
            [
              Nodes::ConditionTreeLeaf.new('quantity', Operators::GREATER_THAN, 10),
              Nodes::ConditionTreeLeaf.new('quantity', Operators::LESS_THAN, 20)
            ]
          ),
          search: 'XBOX',
          segment: 'foo',
          sort: Sort.new([{ field: 'id', ascending: true }]),
          page: Page.new(offset: 2, limit: 10)
        )
        collection.list(caller, filter, Projection.new(%w[id label quantity]))

        expect(rpc_client).to have_received(:call_rpc) do |url, options|
          expect(url).to eq('/forest/rpc/Product/list')
          expect(options[:caller]).to eq(caller)
          expect(options[:method]).to eq(:post)
          expect(options[:payload]).to eq(
            {
              collection_name: 'Product',
              filter: {
                condition_tree: { aggregator: 'And', conditions: [
                  { field: 'quantity', operator: 'greater_than', value: 10 },
                  { field: 'quantity', operator: 'less_than', value: 20 }
                ] },
                search: 'XBOX',
                search_extended: nil,
                segment: 'foo',
                sort: [{ field: 'id', ascending: true }],
                page: { offset: 2, limit: 10 }
              },
              projection: %w[id label quantity]
            }
          )
        end
      end
    end

    context 'when call create' do
      it 'forward the call to the server' do
        data = { label: 'xbox', quantity: 10 }
        collection.create(caller, data)

        expect(rpc_client).to have_received(:call_rpc) do |url, options|
          expect(url).to eq('/forest/rpc/Product/create')
          expect(options[:caller]).to eq(caller)
          expect(options[:method]).to eq(:post)
          expect(options[:payload]).to eq(
            {
              collection_name: 'Product',
              data: [data]
            }
          )
        end
      end
    end

    context 'when call update' do
      it 'forward the call to the server' do
        filter = Filter.new(condition_tree: Nodes::ConditionTreeLeaf.new('id', Operators::EQUAL, 1))
        data = { label: 'xbox', quantity: 10 }
        collection.update(caller, filter, data)

        expect(rpc_client).to have_received(:call_rpc) do |url, options|
          expect(url).to eq('/forest/rpc/Product/update')
          expect(options[:caller]).to eq(caller)
          expect(options[:method]).to eq(:post)
          expect(options[:payload]).to eq(
            {
              collection_name: 'Product',
              filter: filter.to_h,
              patch: data
            }
          )
        end
      end
    end

    context 'when call delete' do
      it 'forward the call to the server' do
        filter = Filter.new(condition_tree: Nodes::ConditionTreeLeaf.new('id', Operators::EQUAL, 1))
        collection.delete(caller, filter)

        expect(rpc_client).to have_received(:call_rpc) do |url, options|
          expect(url).to eq('/forest/rpc/Product/delete')
          expect(options[:caller]).to eq(caller)
          expect(options[:method]).to eq(:post)
          expect(options[:payload]).to eq(
            {
              collection_name: 'Product',
              filter: filter.to_h
            }
          )
        end
      end
    end

    context 'when call aggregate' do
      it 'forward the call to the server' do
        collection.aggregate(caller, Filter.new, Aggregation.new(operation: 'Count'))

        expect(rpc_client).to have_received(:call_rpc) do |url, options|
          expect(url).to eq('/forest/rpc/Product/aggregate')
          expect(options[:caller]).to eq(caller)
          expect(options[:method]).to eq(:post)
          expect(options[:payload]).to eq(
            {
              collection_name: 'Product',
              filter: Filter.new.to_h,
              aggregation: { operation: 'Count', groups: [], field: nil },
              limit: nil
            }
          )
        end
      end
    end

    context 'when call render_chart' do
      it 'forward the call to the server' do
        collection.render_chart(caller, 'my_chart', 1)

        expect(rpc_client).to have_received(:call_rpc) do |url, options|
          expect(url).to eq('/forest/rpc/Product/chart')
          expect(options[:caller]).to eq(caller)
          expect(options[:method]).to eq(:post)
          expect(options[:payload]).to eq(
            {
              collection_name: 'Product',
              chart: 'my_chart',
              record_id: 1,
              parameters: {}
            }
          )
        end
      end

      it 'forward the call with parameters' do
        collection.render_chart(caller, 'my_chart', 1, { 'startDate' => '2024-01-01' })

        expect(rpc_client).to have_received(:call_rpc) do |url, options|
          expect(url).to eq('/forest/rpc/Product/chart')
          expect(options[:caller]).to eq(caller)
          expect(options[:method]).to eq(:post)
          expect(options[:payload]).to eq(
            {
              collection_name: 'Product',
              chart: 'my_chart',
              record_id: 1,
              parameters: { 'startDate' => '2024-01-01' }
            }
          )
        end
      end
    end

    context 'when call execute' do
      it 'forward the call to the server and convert file into data uri' do
        data = {
          'amount' => 1,
          'label' => 'foo',
          'product picture' => {
            'mime_type' => 'image/jpeg',
            'buffer' => "\xFF\xD8\xFF\xE0\x00\x10JFIF\x90\x8B\x0F\x89\xFF\x00\xFF\xD9"
          }
        }

        collection.execute(caller, 'my_action', data)

        expect(rpc_client).to have_received(:call_rpc) do |url, options|
          expect(url).to eq('/forest/rpc/Product/action-execute')
          expect(options[:caller]).to eq(caller)
          expect(options[:method]).to eq(:post)
          expect(options[:payload]).to eq(
            {
              collection_name: 'Product',
              action: 'my_action',
              data: {
                'amount' => 1,
                'label' => 'foo',
                'product picture' => 'data:image/jpeg;base64,/9j/4AAQSkZJRpCLD4n/AP/Z'
              },
              filter: nil
            }
          )
        end
      end

      it 'asks the RPC client to symbolize response keys so ActionResult.parse sees :type' do
        collection.execute(caller, 'my_action', {})

        expect(rpc_client).to have_received(:call_rpc) do |_url, options|
          expect(options[:symbolize_keys]).to be(true)
        end
      end

      it 'returns the action result as-is so :type and other keys reach ActionResult.parse' do
        success_result = {
          type: 'Success',
          message: 'ok',
          invalidated: ['books'],
          html: nil,
          response_headers: {}
        }
        allow(rpc_client).to receive(:call_rpc).and_return(success_result)

        result = collection.execute(caller, 'my_action', {})

        expect(result).to eq(success_result)
        expect(result[:type]).to eq('Success')
      end
    end

    context 'when call get_form' do
      it 'forward the call to the server' do
        collection.get_form(caller, 'my_action')

        expect(rpc_client).to have_received(:call_rpc) do |url, options|
          expect(url).to eq('/forest/rpc/Product/action-form')
          expect(options[:caller]).to eq(caller)
          expect(options[:method]).to eq(:post)
          expect(options[:payload]).to eq(
            {
              collection_name: 'Product',
              action: 'my_action',
              data: {},
              filter: nil,
              metas: nil
            }
          )
        end
      end
    end
  end
end
