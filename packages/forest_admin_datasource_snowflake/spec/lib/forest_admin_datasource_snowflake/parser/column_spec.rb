require 'spec_helper'

RSpec.describe ForestAdminDatasourceSnowflake::Parser::Column do
  describe '.forest_type_for' do
    {
      ODBC::SQL_BIT => 'Boolean',
      ODBC::SQL_INTEGER => 'Number',
      ODBC::SQL_DECIMAL => 'Number',
      ODBC::SQL_DOUBLE => 'Number',
      ODBC::SQL_TYPE_DATE => 'Dateonly',
      ODBC::SQL_TYPE_TIMESTAMP => 'Date',
      ODBC::SQL_TYPE_TIME => 'Time',
      ODBC::SQL_VARCHAR => 'String',
      ODBC::SQL_LONGVARCHAR => 'String',
      ODBC::SQL_VARBINARY => 'Binary',
      ODBC::SQL_GUID => 'Uuid',
      2004 => 'Json'
    }.each do |odbc_type, expected_forest_type|
      it "maps ODBC type #{odbc_type} to '#{expected_forest_type}'" do
        expect(described_class.forest_type_for(odbc_type)).to eq(expected_forest_type)
      end
    end

    it "falls back to 'String' for unknown types" do
      expect(described_class.forest_type_for(99_999)).to eq('String')
    end
  end

  describe '.forest_type_for_snowflake_native' do
    {
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

    it 'returns nil for types not in the override list (let ODBC mapping take over)' do
      expect(described_class.forest_type_for_snowflake_native('NUMBER')).to be_nil
      expect(described_class.forest_type_for_snowflake_native('TIMESTAMP_NTZ')).to be_nil
      expect(described_class.forest_type_for_snowflake_native(nil)).to be_nil
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
