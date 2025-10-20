require 'spec_helper'

module ForestAdminDatasourceActiveRecord
  module Utils
    describe ErrorHandler do
      describe '.handle_errors' do
        context 'when no error occurs' do
          it 'returns the result of the block' do
            result = described_class.handle_errors(:create) { 'success' }
            expect(result).to eq('success')
          end
        end

        context 'when ActiveRecord::RecordNotUnique is raised' do
          it 'raises ValidationError with unicity constraint message' do
            expect do
              described_class.handle_errors(:create) do
                raise ActiveRecord::RecordNotUnique, 'duplicate key'
              end
            end.to raise_error(
              ForestAdminDatasourceToolkit::Exceptions::ValidationError,
              /violates a unicity constraint/
            )
          end
        end

        context 'when ActiveRecord::InvalidForeignKey is raised' do
          context 'with create operation' do
            it 'raises ValidationError with foreign key message for create' do
              expect do
                described_class.handle_errors(:create) do
                  raise ActiveRecord::InvalidForeignKey, 'foreign key violation'
                end
              end.to raise_error(
                ForestAdminDatasourceToolkit::Exceptions::ValidationError,
                /violates a foreign key constraint.*linking to a relation which was deleted/
              )
            end
          end

          context 'with update operation' do
            it 'raises ValidationError with foreign key message for update' do
              expect do
                described_class.handle_errors(:update) do
                  raise ActiveRecord::InvalidForeignKey, 'foreign key violation'
                end
              end.to raise_error(
                ForestAdminDatasourceToolkit::Exceptions::ValidationError,
                /violates a foreign key constraint.*linking to a relation which was deleted/
              )
            end
          end

          context 'with delete operation' do
            it 'raises ValidationError with foreign key message for delete' do
              expect do
                described_class.handle_errors(:delete) do
                  raise ActiveRecord::InvalidForeignKey, 'foreign key violation'
                end
              end.to raise_error(
                ForestAdminDatasourceToolkit::Exceptions::ValidationError,
                /violates a foreign key constraint.*no records are linked/
              )
            end
          end
        end

        context 'when ActiveRecord::RecordInvalid is raised' do
          it 'raises ValidationError with the validation error message' do
            expect do
              described_class.handle_errors(:create) do
                raise ActiveRecord::RecordInvalid, double(errors: double(full_messages: ['Name is required']))
              end
            end.to raise_error(
              ForestAdminDatasourceToolkit::Exceptions::ValidationError
            )
          end
        end

        context 'when a generic error is raised' do
          it 'raises ValidationError with the error message' do
            expect do
              described_class.handle_errors(:create) do
                raise StandardError, 'Something went wrong'
              end
            end.to raise_error(
              ForestAdminDatasourceToolkit::Exceptions::ValidationError,
              'Something went wrong'
            )
          end
        end
      end
    end
  end
end
