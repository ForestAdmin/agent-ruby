require 'spec_helper'

module ForestAdminDatasourceMongoid
  module Parser
    # include ForestAdminDatasourceToolkit
    # include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
    describe Column do
      let(:dummy_class) { Class.new { extend Column } }
      # let(:dummy_class) { Class.new { extend ForestAdminDatasourceMongoid::Parser::Column } }

      let(:columns) do
        {
          'array_field' => Mongoid::Fields::Standard.new(:array_field, type: Array),
          'binary_field' => Mongoid::Fields::Standard.new(:binary_field, type: BSON::Binary),
          'decimal_field' => Mongoid::Fields::Standard.new(:decimal_field, type: BigDecimal),
          'boolean_field' => Mongoid::Fields::Standard.new(:boolean_field, type: Mongoid::Boolean),
          'date_field' => Mongoid::Fields::Standard.new(:date_field, type: Date),
          'datetime_field' => Mongoid::Fields::Standard.new(:datetime_field, type: DateTime),
          'float_field' => Mongoid::Fields::Standard.new(:float_field, type: Float),
          'json_field' => Mongoid::Fields::Standard.new(:json_field, type: Hash),
          'integer_field' => Mongoid::Fields::Standard.new(:integer_field, type: Integer),
          'object_field' => Mongoid::Fields::Standard.new(:object_field, type: Object),
          'bson_object_id_field' => Mongoid::Fields::Standard.new(:bson_object_id_field, type: BSON::ObjectId),
          'range_field' => Mongoid::Fields::Standard.new(:range_field, type: Range),
          'regexp_field' => Mongoid::Fields::Standard.new(:regexp_field, type: Regexp),
          'set_field' => Mongoid::Fields::Standard.new(:set_field, type: Set),
          'string_field' => Mongoid::Fields::Standard.new(:string_field, type: String),
          'stringified_symbol_field' => Mongoid::Fields::Standard.new(:stringified_symbol_field, type: Mongoid::StringifiedSymbol),
          'symbol_field' => Mongoid::Fields::Standard.new(:symbol_field, type: Symbol),
          'time_field' => Mongoid::Fields::Standard.new(:time_field, type: Time),
          'active_support_time_field' => Mongoid::Fields::Standard.new(:active_support_time_field, type: ActiveSupport::TimeWithZone)
        }
      end

      describe 'get_column_type' do
        {
          'array_field' => 'Json',
          'binary_field' => 'Binary',
          'decimal_field' => 'Number',
          'boolean_field' => 'Boolean',
          'date_field' => 'Date',
          'datetime_field' => 'Date',
          'float_field' => 'Number',
          'json_field' => 'Json',
          'integer_field' => 'Number',
          'object_field' => 'Json',
          'bson_object_id_field' => 'String',
          'range_field' => 'Json',
          'regexp_field' => 'String',
          'set_field' => 'Json',
          'string_field' => 'String',
          'stringified_symbol_field' => 'String',
          'symbol_field' => 'String',
          'time_field' => 'Date',
          'active_support_time_field' => 'Date'
        }.each do |field_name, expected_type|
          it "returns correct column type for #{field_name}" do
            column = columns[field_name]
            expect(dummy_class.get_column_type(column)).to eq expected_type
          end
        end
      end

      describe 'get_default_value' do
        it 'returns the default value for columns with a default option' do
          column = Mongoid::Fields::Standard.new(:field_with_default, type: String, default: 'DefaultValue')
          expect(dummy_class.get_default_value(column)).to eq 'DefaultValue'
        end

        it 'returns nil for columns without a default option' do
          column = Mongoid::Fields::Standard.new(:no_default_field, type: String)
          expect(dummy_class.get_default_value(column)).to be_nil
        end
      end

      describe 'get_embedded_fields' do
        it 'returns embedded fields for a model' do
          model = Class.new do
            include Mongoid::Document
            embeds_many :embedded_items
          end

          result = dummy_class.get_embedded_fields(model)
          expect(result.keys).to include('embedded_items')
        end

        it 'returns an empty hash when no embedded fields are present' do
          model = Class.new do
            include Mongoid::Document
            field :simple_field, type: String
          end

          result = dummy_class.get_embedded_fields(model)
          expect(result).to eq({})
        end

        # {
        #   'Boolean' => [Operators::PRESENT, Operators::EQUAL, Operators::NOT_EQUAL],
        #   'Date' => [Operators::PRESENT, Operators::EQUAL, Operators::NOT_EQUAL, Operators::IN, Operators::NOT_IN, Operators::GREATER_THAN, Operators::LESS_THAN],
        #   'String' => [Operators::PRESENT, Operators::EQUAL, Operators::NOT_EQUAL, Operators::IN, Operators::NOT_IN, Operators::MATCH, Operators::NOT_CONTAINS, Operators::NOT_I_CONTAINS]
        # }.each do |type, expected_operators|
        #   it "returns correct operators for type #{type}" do
        #     expect(dummy_class.operators_for_column_type(type)).to eq expected_operators
        #   end
        # end
      end
    end
  end
end
