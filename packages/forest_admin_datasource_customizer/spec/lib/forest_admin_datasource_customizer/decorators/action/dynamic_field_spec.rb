require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Action
      include ForestAdminDatasourceToolkit

      describe DynamicField do
        let(:type) { Types::FieldType::STRING }

        it 'use label value if id is not provided' do
          plain_field = { type: type, label: 'test' }
          field = described_class.new(**plain_field)

          expect(field.id).to eq('test')
        end

        it 'use id value if label is not provided' do
          plain_field = { type: type, id: 'test' }
          field = described_class.new(**plain_field)

          expect(field.label).to eq('test')
        end

        it 'use id value and label value when both are provided' do
          plain_field = { type: type, id: 'test_id', label: 'test' }
          field = described_class.new(**plain_field)

          expect(field.label).to eq('test')
          expect(field.id).to eq('test_id')
        end

        it 'raise an error if id and label are not provided' do
          plain_field = { type: type }

          expect do
            described_class.new(**plain_field)
          end.to raise_error(ForestAdminAgent::Http::Exceptions::BadRequestError, "A field must have an 'id' or a 'label' defined.")
        end

        it 'raise an error if id and label are nil' do
          plain_field = { type: type, id: nil, label: nil }

          expect do
            described_class.new(**plain_field)
          end.to raise_error(ForestAdminAgent::Http::Exceptions::BadRequestError, "A field must have an 'id' or a 'label' defined.")
        end
      end
    end
  end
end
