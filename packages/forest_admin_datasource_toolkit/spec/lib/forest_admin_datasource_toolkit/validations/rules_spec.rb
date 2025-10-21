require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Validations
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
    include ForestAdminDatasourceToolkit::Schema

    describe Rules do
      describe 'get_allowed_operators_for_column_type' do
        context 'with String type' do
          let(:operators) { described_class.get_allowed_operators_for_column_type(PrimitiveType::STRING) }

          it 'includes Match operator' do
            expect(operators).to include(Operators::MATCH)
          end

          it 'includes Like and ILike operators' do
            expect(operators).to include(Operators::LIKE, Operators::I_LIKE)
          end

          it 'includes comparison operators' do
            expect(operators).to include(
              Operators::EQUAL,
              Operators::NOT_EQUAL,
              Operators::LESS_THAN,
              Operators::GREATER_THAN,
              Operators::LESS_THAN_OR_EQUAL,
              Operators::GREATER_THAN_OR_EQUAL
            )
          end

          it 'includes string pattern operators' do
            expect(operators).to include(
              Operators::CONTAINS,
              Operators::NOT_CONTAINS,
              Operators::STARTS_WITH,
              Operators::ENDS_WITH,
              Operators::I_CONTAINS,
              Operators::I_STARTS_WITH,
              Operators::I_ENDS_WITH
            )
          end

          it 'includes length operators' do
            expect(operators).to include(
              Operators::LONGER_THAN,
              Operators::SHORTER_THAN
            )
          end
        end

        context 'with Number type' do
          let(:operators) { described_class.get_allowed_operators_for_column_type(PrimitiveType::NUMBER) }

          it 'does not include Match operator' do
            expect(operators).not_to include(Operators::MATCH)
          end

          it 'includes comparison operators' do
            expect(operators).to include(
              Operators::EQUAL,
              Operators::NOT_EQUAL,
              Operators::LESS_THAN,
              Operators::GREATER_THAN,
              Operators::LESS_THAN_OR_EQUAL,
              Operators::GREATER_THAN_OR_EQUAL
            )
          end
        end

        context 'with Boolean type' do
          let(:operators) { described_class.get_allowed_operators_for_column_type(PrimitiveType::BOOLEAN) }

          it 'does not include Match operator' do
            expect(operators).not_to include(Operators::MATCH)
          end

          it 'includes basic equality operators' do
            expect(operators).to include(
              Operators::EQUAL,
              Operators::NOT_EQUAL,
              Operators::IN,
              Operators::NOT_IN
            )
          end
        end

        context 'with Date type' do
          let(:operators) { described_class.get_allowed_operators_for_column_type(PrimitiveType::DATE) }

          it 'does not include Match operator' do
            expect(operators).not_to include(Operators::MATCH)
          end

          it 'includes date-specific operators' do
            expect(operators).to include(
              Operators::TODAY,
              Operators::YESTERDAY,
              Operators::PAST,
              Operators::FUTURE
            )
          end
        end
      end

      describe 'get_allowed_types_for_column_type' do
        context 'with array of hash (embedded documents)' do
          it 'returns JSON allowed types' do
            column_type = [{ 'street' => 'String', 'city' => 'String', 'zip_code' => 'String' }]
            allowed_types = described_class.get_allowed_types_for_column_type(column_type)
            expect(allowed_types).to eq([PrimitiveType::JSON, nil])
          end
        end

        context 'with hash (embedded document)' do
          it 'returns JSON allowed types' do
            column_type = { 'street' => 'String', 'city' => 'String' }
            allowed_types = described_class.get_allowed_types_for_column_type(column_type)
            expect(allowed_types).to eq([PrimitiveType::JSON, nil])
          end
        end

        context 'with string primitive type' do
          it 'returns String allowed types' do
            allowed_types = described_class.get_allowed_types_for_column_type(PrimitiveType::STRING)
            expect(allowed_types).to eq([PrimitiveType::STRING, nil])
          end
        end
      end

      describe 'get_allowed_types_for_operator' do
        it 'includes String type for Match operator' do
          allowed_types = described_class.get_allowed_types_for_operator(Operators::MATCH)
          expect(allowed_types).to include(PrimitiveType::STRING)
        end

        it 'does not include other types for Match operator' do
          allowed_types = described_class.get_allowed_types_for_operator(Operators::MATCH)
          expect(allowed_types).not_to include(PrimitiveType::NUMBER)
          expect(allowed_types).not_to include(PrimitiveType::BOOLEAN)
          expect(allowed_types).not_to include(PrimitiveType::DATE)
        end
      end
    end
  end
end
