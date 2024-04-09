require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Hook
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminDatasourceToolkit::Decorators
      include ForestAdminDatasourceToolkit::Schema

      describe HookCollectionDecorator do
        subject(:hook_collection_decorator) { described_class }

        let(:caller) { instance_double(ForestAdminDatasourceToolkit::Components::Caller) }
        let(:category) { @datasource_decorator.get_collection('category') }
        let(:aggregation) { instance_double(ForestAdminDatasourceToolkit::Components::Query::Aggregation) }

        before do
          datasource = Datasource.new
          @transaction = collection_build(
            name: 'transaction',
            schema: {
              fields: {
                'id' => numeric_primary_key_build,
                'description' => column_build,
                'amount' => column_build
              }
            },
            list: [],
            create: {},
            update: nil,
            delete: nil,
            aggregate: []
          )
          datasource.add_collection(@transaction)
          @decorated_datasource = DatasourceDecorator.new(datasource, hook_collection_decorator)
          @decorated_transaction = @decorated_datasource.get_collection('transaction')
        end

        it 'schema should not be changed' do
          expect(@decorated_transaction.schema).to eq(@transaction.schema)
        end

        describe 'when adding a before hook' do
          describe 'on a list' do
            it 'call the hook with valid parameters' do
              spy = instance_double(Proc, call: nil)
              @decorated_transaction.add_hook('before', 'list', spy)
              @decorated_transaction.list(caller, Filter.new, Projection.new)

              expect(spy).to have_received(:call).once
            end
          end

          describe 'on a create' do
            it 'call the hook with valid parameters' do
              spy = instance_double(Proc, call: nil)
              @decorated_transaction.add_hook('before', 'create', spy)
              @decorated_transaction.create(caller, [])

              expect(spy).to have_received(:call).once
            end
          end

          describe 'on a update' do
            it 'call the hook with valid parameters' do
              spy = instance_double(Proc, call: nil)
              @decorated_transaction.add_hook('before', 'update', spy)
              @decorated_transaction.update(caller, Filter.new, [])

              expect(spy).to have_received(:call).once
            end
          end

          describe 'on a delete' do
            it 'call the hook with valid parameters' do
              spy = instance_double(Proc, call: nil)
              @decorated_transaction.add_hook('before', 'delete', spy)
              @decorated_transaction.delete(caller, Filter.new)

              expect(spy).to have_received(:call).once
            end
          end

          describe 'on a aggregate' do
            it 'call the hook with valid parameters' do
              spy = instance_double(Proc, call: nil)
              @decorated_transaction.add_hook('before', 'aggregate', spy)
              @decorated_transaction.aggregate(caller, Filter.new, Aggregation.new(operation: 'Count'))

              expect(spy).to have_received(:call).once
            end
          end
        end

        describe 'when adding a after hook' do
          describe 'on a list' do
            it 'call the hook with valid parameters' do
              spy = instance_double(Proc, call: nil)
              @decorated_transaction.add_hook('after', 'list', spy)
              @decorated_transaction.list(caller, Filter.new, Projection.new)

              expect(spy).to have_received(:call).once
            end
          end

          describe 'on a create' do
            it 'call the hook with valid parameters' do
              spy = instance_double(Proc, call: nil)
              @decorated_transaction.add_hook('after', 'create', spy)
              @decorated_transaction.create(caller, [])

              expect(spy).to have_received(:call).once
            end
          end

          describe 'on a update' do
            it 'call the hook with valid parameters' do
              spy = instance_double(Proc, call: nil)
              @decorated_transaction.add_hook('after', 'update', spy)
              @decorated_transaction.update(caller, Filter.new, [])

              expect(spy).to have_received(:call).once
            end
          end

          describe 'on a delete' do
            it 'call the hook with valid parameters' do
              spy = instance_double(Proc, call: nil)
              @decorated_transaction.add_hook('after', 'delete', spy)
              @decorated_transaction.delete(caller, Filter.new)

              expect(spy).to have_received(:call).once
            end
          end

          describe 'on a aggregate' do
            it 'call the hook with valid parameters' do
              spy = instance_double(Proc, call: nil)
              @decorated_transaction.add_hook('after', 'aggregate', spy)
              @decorated_transaction.aggregate(caller, Filter.new, Aggregation.new(operation: 'Count'))

              expect(spy).to have_received(:call).once
            end
          end
        end
      end
    end
  end
end
