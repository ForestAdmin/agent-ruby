require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Validations
    include ForestAdminDatasourceToolkit::Schema
    include ForestAdminDatasourceToolkit::Exceptions
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes
    describe ConditionTreeValidator do
      describe 'when the field is a date' do
        it 'not raise an error when it using the BeforeXHoursAgo operator' do
          collection = build_collection({
                                          schema: {
                                            fields: {
                                              'a_date_field' => ColumnSchema.new(column_type: 'Date', filter_operators: [Operators::BEFORE_X_HOURS_AGO])
                                            }
                                          }
                                        })
          condition_tree = ConditionTreeLeaf.new('a_date_field', Operators::BEFORE_X_HOURS_AGO, 10)

          expect(described_class.validate(condition_tree, collection)).to be_nil
        end

        it 'not raise an error when it using the AfterXHoursAgo operator' do
          collection = build_collection({
                                          schema: {
                                            fields: {
                                              'a_date_field' => ColumnSchema.new(column_type: 'Date', filter_operators: [Operators::AFTER_X_HOURS_AGO])
                                            }
                                          }
                                        })
          condition_tree = ConditionTreeLeaf.new('a_date_field', Operators::AFTER_X_HOURS_AGO, 10)

          expect(described_class.validate(condition_tree, collection)).to be_nil
        end

        it 'not raise an error when it using the PreviousXDaysToDate operator' do
          collection = build_collection({
                                          schema: {
                                            fields: {
                                              'a_date_field' => ColumnSchema.new(column_type: 'Date', filter_operators: [Operators::PREVIOUS_X_DAYS_TO_DATE])
                                            }
                                          }
                                        })
          condition_tree = ConditionTreeLeaf.new('a_date_field', Operators::PREVIOUS_X_DAYS_TO_DATE, 10)

          expect(described_class.validate(condition_tree, collection)).to be_nil
        end

        it 'not raise an error when it using the PreviousXDays operator' do
          collection = build_collection({
                                          schema: {
                                            fields: {
                                              'a_date_field' => ColumnSchema.new(column_type: 'Date', filter_operators: [Operators::PREVIOUS_X_DAYS])
                                            }
                                          }
                                        })
          condition_tree = ConditionTreeLeaf.new('a_date_field', Operators::PREVIOUS_X_DAYS, 10)

          expect(described_class.validate(condition_tree, collection)).to be_nil
        end

        describe 'date operators' do
          let(:collection) do
            build_collection({
                               schema: {
                                 fields: {
                                   'date_field' => ColumnSchema.new(column_type: 'Date', filter_operators: Operators.all)
                                 }
                               }
                             })
          end

          describe 'when it does not support a value' do
            operators = [
              Operators::BLANK,
              Operators::MISSING,
              Operators::PRESENT,
              Operators::YESTERDAY,
              Operators::TODAY,
              Operators::PREVIOUS_QUARTER,
              Operators::PREVIOUS_YEAR,
              Operators::PREVIOUS_MONTH,
              Operators::PREVIOUS_WEEK,
              Operators::PAST,
              Operators::FUTURE,
              Operators::PREVIOUS_WEEK_TO_DATE,
              Operators::PREVIOUS_MONTH_TO_DATE,
              Operators::PREVIOUS_QUARTER_TO_DATE,
              Operators::PREVIOUS_YEAR_TO_DATE
            ]
            operators.each do |operator|
              it "raise an error with #{operator} when a date is given" do
                condition_tree = ConditionTreeLeaf.new('date_field', operator, Date.new)
                expect do
                  described_class.validate(condition_tree, collection)
                end.to raise_error(Exceptions::ValidationError)
              end

              it "not raise an error with #{operator} when the value is empty" do
                condition_tree = ConditionTreeLeaf.new('date_field', operator, nil)
                expect(described_class.validate(condition_tree, collection)).to be_nil
              end
            end
          end

          describe 'when it support only a number' do
            operators = [
              Operators::PREVIOUS_X_DAYS,
              Operators::BEFORE_X_HOURS_AGO,
              Operators::AFTER_X_HOURS_AGO,
              Operators::PREVIOUS_X_DAYS_TO_DATE
            ]
            operators.each do |operator|
              it "raise an error with #{operator} when a date is given" do
                condition_tree = ConditionTreeLeaf.new('date_field', operator, Date.new)
                expect do
                  described_class.validate(condition_tree, collection)
                end.to raise_error(Exceptions::ValidationError)
              end

              it "not raise an error with #{operator} when the value is a number" do
                condition_tree = ConditionTreeLeaf.new('date_field', operator, 1)
                expect(described_class.validate(condition_tree, collection)).to be_nil
              end
            end
          end
        end
      end
    end
  end
end
