require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Schema
    describe ColumnSchema do
      subject(:column) { described_class.new(column_type: 'String') }

      context 'with default values' do
        it { expect(column.is_primary_key).to be false }
        it { expect(column.default_value).to be_nil }
        it { expect(column.is_read_only).to be false }
        it { expect(column.is_sortable).to be false }
        it { expect(column.filter_operators).to eq [] }
        it { expect(column.enum_values).to eq [] }
        it { expect(column.validations).to eq [] }
        it { expect(column.column_type).to eq 'String' }
      end

      context 'when use setters' do
        before do
          column.is_read_only = true
          column.is_sortable = false
          column.filter_operators = ['Equal']
          column.validations = ['validation_foo']
          column.column_type = 'Number'
        end

        it { expect(column.is_read_only).to be true }
        it { expect(column.is_sortable).to be false }
        it { expect(column.filter_operators).to eq ['Equal'] }
        it { expect(column.validations).to eq ['validation_foo'] }
        it { expect(column.column_type).to eq 'Number' }
      end
    end
  end
end
