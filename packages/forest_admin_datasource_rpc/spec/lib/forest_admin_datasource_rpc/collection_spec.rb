require 'spec_helper'
require 'shared/schema'
require 'logger'

module ForestAdminDatasourceRpc
  include ForestAdminDatasourceToolkit::Components::Query
  include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

  describe Collection do
    before do
      logger = instance_double(Logger, log: nil)
      allow(ForestAdminRpcAgent::Facades::Container).to receive_messages(logger: logger, cache: 'secret')
      allow(Utils::RpcClient).to receive(:new).and_return(rpc_client)
    end

    let(:rpc_client) { instance_double(Utils::RpcClient, call_rpc: {}) }
    let(:datasource) { Datasource.new({ uri: 'http://localhost' }, introspection) }
    let(:collection) { datasource.get_collection('Product') }
    let(:caller) { build_caller }

    include_examples 'with introspection'

    context 'when call list' do
      it 'forward the call to the server' do
        collection.list(caller, Filter.new, Projection.new)

        expect(rpc_client).to have_received(:call_rpc) do |url, options|
          expect(url).to eq('/forest/rpc/Product/list')
          expect(options[:method]).to eq(:post)
          expect(options[:payload]).to eq(
            {
              caller: caller.to_h,
              collection_name: 'Product',
              filter: Filter.new.to_h,
              projection: [],
              timezone: 'Europe/Paris'
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
          expect(options[:method]).to eq(:post)
          expect(options[:payload]).to eq(
            {
              collection_name: 'Product',
              caller: {
                id: 1,
                email: 'sarah.connor@skynet.com',
                first_name: 'sarah',
                last_name: 'connor',
                team: 'survivor',
                rendering_id: 1,
                tags: [],
                timezone: 'Europe/Paris',
                permission_level: 'admin',
                role: 'dev',
                request: { ip: '127.0.0.1' },
                project: 'terminator',
                environment: 'Development'
              },
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
              projection: %w[id label quantity],
              timezone: 'Europe/Paris'
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
          expect(options[:method]).to eq(:post)
          expect(options[:payload]).to eq(
            {
              caller: caller.to_h,
              collection_name: 'Product',
              data: data,
              timezone: 'Europe/Paris'
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
          expect(options[:method]).to eq(:post)
          expect(options[:payload]).to eq(
            {
              caller: caller.to_h,
              collection_name: 'Product',
              filter: filter.to_h,
              data: data,
              timezone: 'Europe/Paris'
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
          expect(options[:method]).to eq(:post)
          expect(options[:payload]).to eq(
            {
              caller: caller.to_h,
              collection_name: 'Product',
              filter: filter.to_h,
              timezone: 'Europe/Paris'
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
          expect(options[:method]).to eq(:post)
          expect(options[:payload]).to eq(
            {
              caller: caller.to_h,
              collection_name: 'Product',
              filter: Filter.new.to_h,
              aggregation: { operation: 'Count', groups: [], field: nil },
              limit: nil,
              timezone: 'Europe/Paris'
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
          expect(options[:method]).to eq(:post)
          expect(options[:payload]).to eq(
            {
              caller: caller.to_h,
              collection_name: 'Product',
              name: 'my_chart',
              record_id: 1
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
          expect(options[:method]).to eq(:post)
          expect(options[:payload]).to eq(
            {
              caller: caller.to_h,
              collection_name: 'Product',
              action: 'my_action',
              data: {
                'amount' => 1,
                'label' => 'foo',
                'product picture' => 'data:image/jpeg;base64,/9j/4AAQSkZJRpCLD4n/AP/Z'
              },
              filter: nil,
              timezone: 'Europe/Paris'
            }
          )
        end
      end
    end

    context 'when call get_form' do
      it 'forward the call to the server' do
        collection.get_form(caller, 'my_action')

        expect(rpc_client).to have_received(:call_rpc) do |url, options|
          expect(url).to eq('/forest/rpc/Product/action-form')
          expect(options[:method]).to eq(:post)
          expect(options[:payload]).to eq(
            {
              caller: caller.to_h,
              collection_name: 'Product',
              action: 'my_action',
              data: {},
              filter: nil,
              metas: nil,
              timezone: 'Europe/Paris'
            }
          )
        end
      end
    end
  end
end
