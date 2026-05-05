require 'spec_helper'

RSpec.describe ForestAdminDatasourceSnowflake::Parser::Column do
  describe '.forest_type_for_snowflake_native' do
    {
      'NUMBER' => 'Number',
      'DECIMAL' => 'Number',
      'INTEGER' => 'Number',
      'BIGINT' => 'Number',
      'FLOAT' => 'Number',
      'DOUBLE' => 'Number',
      'BOOLEAN' => 'Boolean',
      'TEXT' => 'String',
      'VARCHAR' => 'String',
      'CHAR' => 'String',
      'DATE' => 'Dateonly',
      'TIME' => 'Time',
      'TIMESTAMP' => 'Date',
      'TIMESTAMP_NTZ' => 'Date',
      'TIMESTAMP_LTZ' => 'Date',
      'TIMESTAMP_TZ' => 'Date',
      'VARIANT' => 'Json',
      'OBJECT' => 'Json',
      'ARRAY' => 'Json',
      'BINARY' => 'Binary',
      'VARBINARY' => 'Binary'
    }.each do |native_type, expected_forest_type|
      it "maps Snowflake native type '#{native_type}' to '#{expected_forest_type}'" do
        expect(described_class.forest_type_for_snowflake_native(native_type)).to eq(expected_forest_type)
      end
    end

    it 'is case-insensitive' do
      expect(described_class.forest_type_for_snowflake_native('variant')).to eq('Json')
    end

    it "falls back to 'String' for unknown / nil types" do
      expect(described_class.forest_type_for_snowflake_native('SOMETHING_NEW')).to eq('String')
      expect(described_class.forest_type_for_snowflake_native(nil)).to eq('String')
    end
  end

  describe '.operators_for_column_type' do
    let(:base_operators) { [Operators::PRESENT, Operators::BLANK, Operators::MISSING] }

    it 'returns only base operators for unknown / non-string input' do
      expect(described_class.operators_for_column_type(nil)).to match_array(base_operators)
    end

    it 'includes equality + ordering for Number' do
      ops = described_class.operators_for_column_type('Number')
      expect(ops).to include(*base_operators)
      expect(ops).to include(Operators::EQUAL, Operators::NOT_EQUAL, Operators::IN, Operators::NOT_IN)
      expect(ops).to include(Operators::LESS_THAN, Operators::GREATER_THAN)
      expect(ops).not_to include(Operators::CONTAINS, Operators::LIKE)
    end

    it 'includes equality for Boolean but no ordering or string ops' do
      ops = described_class.operators_for_column_type('Boolean')
      expect(ops).to include(Operators::EQUAL, Operators::NOT_EQUAL)
      expect(ops).not_to include(Operators::LESS_THAN, Operators::CONTAINS)
    end

    it 'includes string-specific operators for String' do
      ops = described_class.operators_for_column_type('String')
      expect(ops).to include(Operators::CONTAINS, Operators::I_CONTAINS, Operators::STARTS_WITH, Operators::LIKE,
                             Operators::I_LIKE, Operators::SHORTER_THAN, Operators::LONGER_THAN)
    end

    it 'includes ordering for Date / Dateonly / Time' do
      %w[Date Dateonly Time].each do |type|
        ops = described_class.operators_for_column_type(type)
        expect(ops).to include(Operators::LESS_THAN, Operators::GREATER_THAN, Operators::EQUAL),
                       "expected ordering ops for #{type}"
      end
    end
  end
end
