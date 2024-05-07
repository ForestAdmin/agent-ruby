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
          @transaction = collection_build(
            name: 'transaction',
            schema: {
              fields: {
                'id' => numeric_primary_key_build,
                'description' => column_build,
                'amount_in_euro' => column_build
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
          # describe('on create', () => {
          #       test('it should call the handler', async () => {
          #         const spy = jest.spyOn(transactions, 'create');
          #         const handler = jest.fn();
          #
          #         const currentCaller = factories.caller.build();
          #         const currentData = [factories.recordData.build()];
          #         const context = new CreateOverrideCustomizationContext(
          #           transactions,
          #           currentCaller,
          #           currentData,
          #         );
          #
          #         decoratedTransactions.addCreateHandler(handler);
          #         await decoratedTransactions.create(currentCaller, currentData);
          #
          #         expect(spy).not.toHaveBeenCalled();
          #         expect(handler).toHaveBeenCalledTimes(1);
          #
          #         const handlerArguments = handler.mock.calls[0][0];
          #         expect(handlerArguments.caller).toEqual(context.caller);
          #         expect(handlerArguments.data).toEqual(context.data);
          #       });
          #     });

          context 'when create' do
            it 'calls the handler' do
              handler = instance_double(Proc, call: nil)
              Context::CreateOverrideCustomizationContext.new(@decorated_transaction, caller, [])
              # handler = Proc.new do |context|
              #   expect(context.caller).to eq(caller)
              # end

              @decorated_transaction.add_create_handler(handler)
              @decorated_transaction.create(caller, [])

              expect(handler).to have_received(:call).once
            end
          end

          context 'when update' do
            it 'calls the handler' do
              handler = instance_double(Proc, call: nil)

              @decorated_transaction.add_update_handler(handler)
              @decorated_transaction.update(caller, Filter.new, [])

              expect(handler).to have_received(:call).once
            end
          end

          context 'when delete' do
            it 'calls the handler' do
              handler = instance_double(Proc, call: nil)

              @decorated_transaction.add_delete_handler(handler)
              @decorated_transaction.delete(caller, Filter.new)

              expect(handler).to have_received(:call).once
            end
          end
        end
      end
    end
  end
end
