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
        let(:aggregation) { instance_double(ForestAdminDatasourceToolkit::Components::Query::Aggregation) }

        before do
          datasource = Datasource.new
          @transaction = build_collection(
            name: 'transaction',
            schema: {
              fields: {
                'id' => build_numeric_primary_key,
                'description' => build_column,
                'amount' => build_column
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
              @decorated_transaction.add_hook('Before', 'List', spy)
              @decorated_transaction.list(caller, Filter.new, Projection.new)

              expect(spy).to have_received(:call).once
            end
          end

          describe 'on a create' do
            it 'call the hook with valid parameters' do
              spy = instance_double(Proc, call: nil)
              @decorated_transaction.add_hook('Before', 'Create', spy)
              @decorated_transaction.create(caller, [])

              expect(spy).to have_received(:call).once
            end
          end

          describe 'on a update' do
            it 'call the hook with valid parameters' do
              spy = instance_double(Proc, call: nil)
              @decorated_transaction.add_hook('Before', 'Update', spy)
              @decorated_transaction.update(caller, Filter.new, [])

              expect(spy).to have_received(:call).once
            end
          end

          describe 'on a delete' do
            it 'call the hook with valid parameters' do
              spy = instance_double(Proc, call: nil)
              @decorated_transaction.add_hook('Before', 'Delete', spy)
              @decorated_transaction.delete(caller, Filter.new)

              expect(spy).to have_received(:call).once
            end
          end

          describe 'on a aggregate' do
            it 'call the hook with valid parameters' do
              spy = instance_double(Proc, call: nil)
              @decorated_transaction.add_hook('Before', 'Aggregate', spy)
              @decorated_transaction.aggregate(caller, Filter.new, Aggregation.new(operation: 'Count'))

              expect(spy).to have_received(:call).once
            end
          end
        end

        describe 'when adding a after hook' do
          describe 'on a list' do
            it 'call the hook with valid parameters' do
              spy = instance_double(Proc, call: nil)
              @decorated_transaction.add_hook('After', 'List', spy)
              @decorated_transaction.list(caller, Filter.new, Projection.new)

              expect(spy).to have_received(:call).once
            end
          end

          describe 'on a create' do
            it 'call the hook with valid parameters' do
              spy = instance_double(Proc, call: nil)
              @decorated_transaction.add_hook('After', 'Create', spy)
              @decorated_transaction.create(caller, [])

              expect(spy).to have_received(:call).once
            end
          end

          describe 'on a update' do
            it 'call the hook with valid parameters' do
              spy = instance_double(Proc, call: nil)
              @decorated_transaction.add_hook('After', 'Update', spy)
              @decorated_transaction.update(caller, Filter.new, [])

              expect(spy).to have_received(:call).once
            end
          end

          describe 'on a delete' do
            it 'call the hook with valid parameters' do
              spy = instance_double(Proc, call: nil)
              @decorated_transaction.add_hook('After', 'Delete', spy)
              @decorated_transaction.delete(caller, Filter.new)

              expect(spy).to have_received(:call).once
            end
          end

          describe 'on a aggregate' do
            it 'call the hook with valid parameters' do
              spy = instance_double(Proc, call: nil)
              @decorated_transaction.add_hook('After', 'Aggregate', spy)
              @decorated_transaction.aggregate(caller, Filter.new, Aggregation.new(operation: 'Count'))

              expect(spy).to have_received(:call).once
            end
          end
        end
      end
    end
  end
end
