require 'spec_helper'

module ForestAdminDatasourceActiveRecord
  module Parser
    describe Column do
      let(:dummy_class) { Class.new { extend Column } }
      let(:columns) { User.columns_hash }

      describe 'get_column_type' do
        it { expect(dummy_class.get_column_type(User, columns['string_field'])).to eq 'String' }
        it { expect(dummy_class.get_column_type(User, columns['text_field'])).to eq 'String' }
        it { expect(dummy_class.get_column_type(User, columns['boolean_field'])).to eq 'Boolean' }
        it { expect(dummy_class.get_column_type(User, columns['date_field'])).to eq 'Dateonly' }
        it { expect(dummy_class.get_column_type(User, columns['datetime_field'])).to eq 'Date' }
        it { expect(dummy_class.get_column_type(User, columns['timestamptz_field'])).to eq 'Date' }
        it { expect(dummy_class.get_column_type(User, columns['integer_field'])).to eq 'Number' }
        it { expect(dummy_class.get_column_type(User, columns['float_field'])).to eq 'Number' }
        it { expect(dummy_class.get_column_type(User, columns['decimal_field'])).to eq 'Number' }
        it { expect(dummy_class.get_column_type(User, columns['json_field'])).to eq 'Json' }
        it { expect(dummy_class.get_column_type(User, columns['time_field'])).to eq 'Time' }
        it { expect(dummy_class.get_column_type(User, columns['binary_field'])).to eq 'Binary' }
        it { expect(dummy_class.get_column_type(User, columns['enum_field'])).to eq 'Enum' }

        it 'return string type by default when column type is unknown' do
          logger = instance_double(Logger, log: nil)
          allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(logger)
          column = instance_double(
            ActiveRecord::ConnectionAdapters::SQLite3::Column,
            name: 'foo',
            type: 'unknown type'
          )

          expect(dummy_class.get_column_type(User, column)).to eq 'String'
        end
      end

      describe 'get_enum_values' do
        it 'return an empty array if column is not Enum' do
          expect(dummy_class.get_enum_values(User, columns['string_field'])).to eq []
        end

        it 'return the enum values' do
          expect(dummy_class.get_enum_values(User, columns['enum_field'])).to eq(%w[draft published archived trashed])
        end
      end
    end
  end
end
