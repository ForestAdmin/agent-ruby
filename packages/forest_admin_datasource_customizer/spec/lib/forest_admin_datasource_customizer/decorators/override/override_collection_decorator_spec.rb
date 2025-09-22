require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Override
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminDatasourceToolkit::Decorators

      describe OverrideCollectionDecorator do
        subject(:override_collection_decorator) { described_class }

        let(:caller) { instance_double(ForestAdminDatasourceToolkit::Components::Caller) }

        before do
          datasource = Datasource.new
          @transaction = build_collection(
            name: 'transaction',
            schema: {
              fields: {
                'id' => build_numeric_primary_key,
                'description' => build_column,
                'amount_in_euro' => build_column
              }
            },
            list: [],
            create: {},
            update: nil,
            delete: nil,
            aggregate: []
          )
          datasource.add_collection(@transaction)
          @decorated_datasource = DatasourceDecorator.new(datasource, override_collection_decorator)
          @decorated_transaction = @decorated_datasource.get_collection('transaction')
        end

        it 'schema should not be changed' do
          expect(@decorated_transaction.schema).to eq(@transaction.schema)
        end

        context 'when no handler are set' do
          context 'when create' do
            it 'calls the original collection behavior' do
              allow(@decorated_transaction).to receive(:create).and_return(nil)
              @decorated_transaction.create(caller, [])

              expect(@decorated_transaction).to have_received(:create)
            end
          end

          context 'when update' do
            it 'calls the original collection behavior' do
              allow(@decorated_transaction).to receive(:update).and_return(nil)
              @decorated_transaction.update(caller, Filter.new, [])

              expect(@decorated_transaction).to have_received(:update)
            end
          end

          context 'when delete' do
            it 'calls the original collection behavior' do
              allow(@decorated_transaction).to receive(:delete).and_return(nil)
              @decorated_transaction.delete(caller, Filter.new)

              expect(@decorated_transaction).to have_received(:delete)
            end
          end
        end

        context 'when setting up override' do
          context 'when create' do
            it 'calls the handler' do
              handler = instance_double(Proc, call: nil)

              @decorated_transaction.add_create_handler(handler)
              @decorated_transaction.create(caller, [])

              expect(handler).to have_received(:call).once do |context|
                expect(context.caller).to eq(caller)
                expect(context.data).to eq([])
              end
            end
          end

          context 'when update' do
            it 'calls the handler' do
              handler = instance_double(Proc, call: nil)

              @decorated_transaction.add_update_handler(handler)
              @decorated_transaction.update(caller, Filter.new, [])

              expect(handler).to have_received(:call).once do |context|
                expect(context.caller).to eq(caller)
                expect(context.filter).to be_a(Filter)
                expect(context.patch).to eq([])
              end
            end
          end

          context 'when delete' do
            it 'calls the handler' do
              handler = instance_double(Proc, call: nil)

              @decorated_transaction.add_delete_handler(handler)
              @decorated_transaction.delete(caller, Filter.new)

              expect(handler).to have_received(:call).once do |context|
                expect(context.caller).to eq(caller)
                expect(context.filter).to be_a(Filter)
              end
            end
          end
        end
      end
    end
  end
end
