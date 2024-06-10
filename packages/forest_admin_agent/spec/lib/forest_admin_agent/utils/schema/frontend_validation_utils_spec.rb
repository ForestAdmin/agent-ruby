require 'spec_helper'

module ForestAdminAgent
  module Utils
    module Schema
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

      describe FrontendValidationUtils do
        subject(:frontend_validation_utils) { described_class }

        context 'when using convert_validation_list' do
          it 'works with null validation' do
            column = column_build
            expect(frontend_validation_utils.convert_validation_list(column)).to be_empty
          end

          it 'works with empty validation' do
            column = column_build(validations: [])
            expect(frontend_validation_utils.convert_validation_list(column)).to be_empty
          end

          it 'works with supported handlers (strings)' do
            column = numeric_primary_key_build(validations: [
                                                 { operator: Operators::PRESENT },
                                                 { operator: Operators::LESS_THAN, value: 34 },
                                                 { operator: Operators::GREATER_THAN, value: 60 }
                                               ])
            expect(frontend_validation_utils.convert_validation_list(column)).to eq([
                                                                                      { message: 'Field is required', type: 'is present' },
                                                                                      { message: 'Value must be lower than 34', type: 'is less than', value: 34 },
                                                                                      { message: 'Value must be greater than 60', type: 'is greater than', value: 60 }
                                                                                    ])
          end

          it 'works with supported handlers (date)' do
            column = column_build(column_type: 'Date', validations: [
                                    { operator: Operators::BEFORE, value: '2010-01-01T00:00:00Z' },
                                    { operator: Operators::AFTER, value: '2010-01-01T00:00:00Z' }
                                  ])
            expect(frontend_validation_utils.convert_validation_list(column)).to eq([
                                                                                      { message: 'Value must be before 2010-01-01T00:00:00Z', type: 'is before', value: '2010-01-01T00:00:00Z' },
                                                                                      { message: 'Value must be after 2010-01-01T00:00:00Z', type: 'is after', value: '2010-01-01T00:00:00Z' }
                                                                                    ])
          end

          it 'works with supported handlers (string)' do
            column = column_build(column_type: 'Number', validations: [
                                    { operator: Operators::LONGER_THAN, value: 34 },
                                    { operator: Operators::SHORTER_THAN, value: 60 },
                                    { operator: Operators::CONTAINS, value: 'abc' },
                                    { operator: Operators::MATCH, value: '/abc/' }
                                  ])
            expect(frontend_validation_utils.convert_validation_list(column)).to eq([
                                                                                      { message: 'Value must be longer than 34 characters', type: 'is longer than', value: 34 },
                                                                                      { message: 'Value must be shorter than 60 characters', type: 'is shorter than', value: 60 },
                                                                                      { message: 'Value must contain abc', type: 'is contains', value: 'abc' },
                                                                                      { message: 'Value must match /abc/', type: 'is like', value: '/abc/' }
                                                                                    ])
          end

          it 'works with supported handlers (fake enum)' do
            column = column_build(column_type: 'String', validations: [
                                    { operator: Operators::IN, value: %w[a b c] }
                                  ])
            expect(frontend_validation_utils.convert_validation_list(column)).to eq([
                                                                                      { message: 'Value must match /(a|b|c)/g', type: 'is like', value: '/(a|b|c)/g' }
                                                                                    ])
          end

          it 'works with duplication' do
            column = numeric_primary_key_build(validations: [
                                                 { operator: Operators::PRESENT },
                                                 { operator: Operators::PRESENT },
                                                 { operator: Operators::LESS_THAN, value: 34 },
                                                 { operator: Operators::LESS_THAN, value: 40 },
                                                 { operator: Operators::GREATER_THAN, value: 60 },
                                                 { operator: Operators::GREATER_THAN, value: 80 },
                                                 { operator: Operators::GREATER_THAN, value: 70 },
                                                 { operator: Operators::MATCH, value: '/a/' },
                                                 { operator: Operators::MATCH, value: '/b/' }
                                               ])
            expect(frontend_validation_utils.convert_validation_list(column)).to eq([
                                                                                      { message: 'Field is required', type: 'is present' },
                                                                                      { message: 'Value must be lower than 34', type: 'is less than', value: 34 },
                                                                                      { message: 'Value must be greater than 80', type: 'is greater than', value: 80 },
                                                                                      { message: 'Value must match /^(?=a)(?=b).*$/i', type: 'is like', value: '/^(?=a)(?=b).*$/i' }
                                                                                    ])
          end

          it 'works with rule expansion (not in with null)' do
            column = column_build(column_type: 'String', validations: [
                                    { operator: Operators::NOT_IN, value: ['a', 'b', nil] }
                                  ])
            expect(frontend_validation_utils.convert_validation_list(column)).to eq([
                                                                                      { message: 'Value must match /(?!(a|b))/g', type: 'is like', value: '/(?!(a|b))/g' }
                                                                                    ])
          end

          it 'skips validation which cannot be translated (depends on current time)' do
            column = column_build(column_type: 'Date', validations: [
                                    { operator: Operators::PREVIOUS_QUARTER }
                                  ])
            expect(frontend_validation_utils.convert_validation_list(column)).to be_empty
          end

          it 'skips validation which cannot be translated (fake enum with null)' do
            column = column_build(column_type: 'String', validations: [
                                    { operator: Operators::IN, value: ['a', 'b', nil] }
                                  ])
            expect(frontend_validation_utils.convert_validation_list(column)).to eq([
                                                                                      { message: 'Value must match /(a|b)/g', type: 'is like', value: '/(a|b)/g' }
                                                                                    ])
          end
        end
      end
    end
  end
end
