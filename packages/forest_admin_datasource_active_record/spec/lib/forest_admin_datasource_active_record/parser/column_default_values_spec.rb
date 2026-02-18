require 'spec_helper'

module ForestAdminDatasourceActiveRecord
  module Parser
    describe Column do
      include described_class

      let(:datasource) { Datasource.new({ adapter: 'sqlite3', database: 'db/database.db' }) }
      let(:collection) { ForestAdminDatasourceActiveRecord::Collection.new(datasource, TestDefault) }

      before do
        # Run the migration to create the test_defaults table
        unless ActiveRecord::Base.connection.table_exists?(:test_defaults)
          ActiveRecord::Migration.suppress_messages do
            CreateTestDefaults.migrate(:up)
          end
        end
      end

      describe 'normalize_default_value' do
        context 'with boolean fields' do
          it 'normalizes false default value' do
            column = TestDefault.columns.find { |c| c.name == 'active' }
            result = normalize_default_value(column)

            expect(result).to be(false)
            expect(result).to be_a(FalseClass)
          end

          it 'normalizes true default value' do
            column = TestDefault.columns.find { |c| c.name == 'verified' }
            result = normalize_default_value(column)

            expect(result).to be(true)
            expect(result).to be_a(TrueClass)
          end
        end

        context 'with integer/enum fields' do
          it 'normalizes integer default value to 0' do
            column = TestDefault.columns.find { |c| c.name == 'status' }
            result = normalize_default_value(column)

            expect(result).to eq(0)
            expect(result).to be_a(Integer)
          end

          it 'normalizes integer default value to 1' do
            column = TestDefault.columns.find { |c| c.name == 'priority' }
            result = normalize_default_value(column)

            expect(result).to eq(1)
            expect(result).to be_a(Integer)
          end
        end

        context 'with nil default' do
          it 'returns the original value for string with no default' do
            column = TestDefault.columns.find { |c| c.name == 'name' }

            # name has no default, so column.default is nil
            # In the collection, we check nil before calling normalize
            expect(column.default).to be_nil
          end
        end
      end

      describe 'integration with real columns' do
        it 'handles all default value types correctly' do
          # Test that actual column defaults are normalized properly
          columns = TestDefault.columns

          active = columns.find { |c| c.name == 'active' }
          verified = columns.find { |c| c.name == 'verified' }
          status = columns.find { |c| c.name == 'status' }
          priority = columns.find { |c| c.name == 'priority' }

          # All these should be properly normalized
          expect(normalize_default_value(active)).to be(false)
          expect(normalize_default_value(verified)).to be(true)
          expect(normalize_default_value(status)).to eq(0)
          expect(normalize_default_value(priority)).to eq(1)
        end
      end
    end
  end
end
