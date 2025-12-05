require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Validations
    include ForestAdminDatasourceToolkit::Schema
    include ForestAdminDatasourceToolkit::Exceptions
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
    describe FieldValidator do
      before do
        @datasource = Datasource.new
        @collection_cars = Collection.new(@datasource, 'cars')
        @collection_cars.add_fields(
          {
            'id' => ColumnSchema.new(column_type: Concerns::PrimitiveTypes::NUMBER, is_primary_key: true),
            'owner' => Relations::OneToOneSchema.new(
              origin_key: 'id',
              origin_key_target: 'id',
              foreign_collection: 'owner'
            )
          }
        )
        @collection_owners = Collection.new(@datasource, 'owner')
        @collection_owners.add_fields(
          {
            'id' => ColumnSchema.new(column_type: Concerns::PrimitiveTypes::NUMBER, is_primary_key: true),
            'name' => ColumnSchema.new(column_type: Concerns::PrimitiveTypes::STRING),
            'address' => Relations::OneToOneSchema.new(
              origin_key: 'id',
              origin_key_target: 'id',
              foreign_collection: 'address'
            )
          }
        )

        @datasource.add_collection(@collection_cars)
        @datasource.add_collection(@collection_owners)
      end

      context 'when validate is called' do
        it 'does not throw if the field exist on the collection' do
          expect { described_class.validate(@collection_cars, 'id') }.not_to raise_error
        end

        it 'does not throw if the given value is null' do
          expect { described_class.validate(@collection_cars, 'id', [nil]) }.not_to raise_error
        end

        it 'throws if the field does not exists' do
          expect do
            described_class.validate(@collection_cars,
                                     '__not_defined')
          end.to raise_error(ValidationError, "Column not found: 'cars.__not_defined'")
        end

        it 'throws if the relation does not exists' do
          expect do
            described_class.validate(@collection_cars,
                                     '__not_defined:id')
          end.to raise_error(ValidationError, "Relation not found: 'cars.__not_defined'")
        end

        it 'throws if the field is not of column type' do
          expect do
            described_class.validate(@collection_cars,
                                     'owner')
          end.to raise_error(ValidationError,
                             "Unexpected field type: 'cars.owner' (found 'OneToOne' expected 'Column')")
        end

        context 'when validating relationship fields' do
          it 'validates fields on other collections' do
            expect { described_class.validate(@collection_cars, 'owner:name') }.not_to raise_error
          end

          it 'throws when the requested field is of type column' do
            expect do
              described_class.validate(@collection_cars,
                                       'id:address')
            end.to raise_error(ValidationError,
                               "Unexpected field type: 'cars.id' (found 'Column')")
          end
        end

        context 'when validating a json field with an array value' do
          it 'allows the array as a value' do
            collection = Collection.new(@datasource, 'owner')
            collection.add_fields(
              {
                'jsonField' => ColumnSchema.new(column_type: Concerns::PrimitiveTypes::JSON,
                                                filter_operators: [Operators::IN])
              }
            )

            expect { described_class.validate(collection, 'jsonField', [%w[item1 item2]]) }.not_to raise_error
          end
        end

        context 'with field of type boolean' do
          it 'valid value type should not throw error' do
            expect do
              described_class.validate_value('booleanField', ColumnSchema.new(column_type: Concerns::PrimitiveTypes::BOOLEAN),
                                             true)
            end.not_to raise_error
          end

          it 'with field of type boolean with valid value should not throw' do
            column = ColumnSchema.new(column_type: Concerns::PrimitiveTypes::BOOLEAN)
            expect do
              described_class.validate_value('boolean', column,
                                             'not a boolean')
            end.to raise_error(ValidationError,
                               "The given value has a wrong type for 'boolean': not a boolean.\n Expects [\"Boolean\", nil]")
          end
        end

        context 'with field of type date|dateonly|timeonly' do
          it 'valid value (string) type should not throw error' do
            expect do
              described_class.validate_value('date', ColumnSchema.new(column_type: Concerns::PrimitiveTypes::DATE),
                                             '2022-01-13T17:16:04.000Z')
            end.not_to raise_error
          end

          it 'valid value (ruby date) type should not throw error' do
            expect do
              described_class.validate_value('date', ColumnSchema.new(column_type: Concerns::PrimitiveTypes::DATE),
                                             Date.new)
            end.not_to raise_error
          end

          it 'invalid value type should throw error' do
            expect do
              described_class.validate_value('date', ColumnSchema.new(column_type: Concerns::PrimitiveTypes::DATE),
                                             'definitely-not-a-date')
            end.to raise_error(ValidationError,
                               "The given value has a wrong type for 'date': definitely-not-a-date.\n Expects [\"Date\", nil]")
          end
        end

        context 'with field of type enum' do
          it 'valid value type should not throw error' do
            expect do
              described_class.validate_value('enum',
                                             ColumnSchema.new(column_type: Concerns::PrimitiveTypes::ENUM, enum_values: %w[a b c]), 'a')
            end.not_to raise_error
          end

          it 'invalid value type should throw error' do
            expect do
              described_class.validate_value('enum',
                                             ColumnSchema.new(column_type: Concerns::PrimitiveTypes::ENUM, enum_values: %w[a b c]), 'd')
            end.to raise_error(ValidationError, 'The given enum value(s) d is not listed in ["a", "b", "c"]')
          end
        end

        context 'with field of type json' do
          it 'valid (string) value type should not throw error' do
            expect do
              described_class.validate_value('json', ColumnSchema.new(column_type: Concerns::PrimitiveTypes::JSON),
                                             '{"foo": "bar"}')
            end.not_to raise_error
          end

          it 'valid (json) value type should not throw error' do
            expect do
              described_class.validate_value('json', ColumnSchema.new(column_type: Concerns::PrimitiveTypes::JSON),
                                             { foo: 'bar' })
            end.not_to raise_error
          end

          it 'valid (json array) value type should not throw error' do
            expect do
              described_class.validate_value('json', ColumnSchema.new(column_type: Concerns::PrimitiveTypes::JSON),
                                             ['email'])
            end.not_to raise_error
          end

          it 'a failed declaration of an plain object should also be a valid a json' do
            expect do
              described_class.validate_value('json', ColumnSchema.new(column_type: Concerns::PrimitiveTypes::JSON),
                                             '{not:"a:" valid plain object but it is a valid json')
            end.not_to raise_error
          end
        end

        context 'with field of type number' do
          it 'valid value type should not throw error' do
            expect do
              described_class.validate_value('number', ColumnSchema.new(column_type: Concerns::PrimitiveTypes::NUMBER),
                                             1)
            end.not_to raise_error
          end

          it 'valid value type should not throw error (string number)' do
            expect do
              described_class.validate_value('number', ColumnSchema.new(column_type: Concerns::PrimitiveTypes::NUMBER),
                                             '27')
            end.not_to raise_error
          end

          it 'invalid value type should throw error' do
            expect do
              described_class.validate_value('number', ColumnSchema.new(column_type: Concerns::PrimitiveTypes::NUMBER),
                                             'not a number')
            end.to raise_error(ValidationError,
                               "The given value has a wrong type for 'number': not a number.\n Expects [\"Number\", nil]")
          end
        end

        context 'with field of type point' do
          it 'valid value type should not throw error' do
            expect do
              described_class.validate_value('point', ColumnSchema.new(column_type: Concerns::PrimitiveTypes::POINT),
                                             '1,2')
            end.not_to raise_error
          end

          it 'invalid value type should throw error' do
            expect do
              described_class.validate_value('point', ColumnSchema.new(column_type: Concerns::PrimitiveTypes::POINT),
                                             'd,a')
            end.to raise_error(ValidationError,
                               "The given value has a wrong type for 'point': d,a.\n Expects [\"Point\", nil]")
          end
        end

        context 'with field of type string' do
          it 'valid value type should not throw error' do
            expect do
              described_class.validate_value('string', ColumnSchema.new(column_type: Concerns::PrimitiveTypes::STRING),
                                             'test')
            end.not_to raise_error
          end

          it 'invalid value type should throw error' do
            expect do
              described_class.validate_value('string', ColumnSchema.new(column_type: Concerns::PrimitiveTypes::STRING),
                                             1)
            end.to raise_error(ValidationError,
                               "The given value has a wrong type for 'string': 1.\n Expects [\"String\", nil]")
          end
        end

        context 'with field of type uuid' do
          it 'valid value (uuid v1) type should not throw error' do
            expect do
              described_class.validate_value('uuid', ColumnSchema.new(column_type: Concerns::PrimitiveTypes::UUID),
                                             'a7147d1c-7d44-11ec-90d6-0242ac120003')
            end.not_to raise_error
          end

          it 'valid value (uuid v4) type should not throw error' do
            expect do
              described_class.validate_value('uuid', ColumnSchema.new(column_type: Concerns::PrimitiveTypes::UUID),
                                             '05db90e8-6e72-4278-888d-9b127c91470e')
            end.not_to raise_error
          end

          it 'invalid value type should throw error' do
            expect do
              described_class.validate_value('uuid', ColumnSchema.new(column_type: Concerns::PrimitiveTypes::UUID),
                                             'not-a-valid-uuid')
            end.to raise_error(ValidationError,
                               "The given value has a wrong type for 'uuid': not-a-valid-uuid.\n Expects [\"Uuid\", nil]")
          end

          context 'when it is an id' do
            it 'given null value should throw an error' do
              expect do
                described_class.validate_value_for_id('uuid', ColumnSchema.new(column_type: Concerns::PrimitiveTypes::UUID),
                                                      nil)
              end.to raise_error(ValidationError,
                                 "The given value has a wrong type for 'uuid': .\n Expects [\"Uuid\"]")
            end

            it 'given non null value should not throw an error' do
              expect do
                described_class.validate_value_for_id('uuid', ColumnSchema.new(column_type: Concerns::PrimitiveTypes::UUID),
                                                      '05db90e8-6e72-4278-888d-9b127c91470e')
              end.not_to raise_error
            end
          end
        end

        context 'with template strings (context variables)' do
          it 'skips validation for template string on uuid field' do
            expect do
              described_class.validate_value('id', ColumnSchema.new(column_type: Concerns::PrimitiveTypes::UUID),
                                             '{{collection_financing.selectedRecord.id}}')
            end.not_to raise_error
          end

          it 'skips validation for template string on number field' do
            expect do
              described_class.validate_value('count', ColumnSchema.new(column_type: Concerns::PrimitiveTypes::NUMBER),
                                             '{{currentUser.team.id}}')
            end.not_to raise_error
          end

          it 'skips validation for template string on date field' do
            expect do
              described_class.validate_value('date', ColumnSchema.new(column_type: Concerns::PrimitiveTypes::DATE),
                                             '{{currentUser.createdAt}}')
            end.not_to raise_error
          end

          it 'does not skip validation for strings that look similar but are not template strings' do
            expect do
              described_class.validate_value('uuid', ColumnSchema.new(column_type: Concerns::PrimitiveTypes::UUID),
                                             '{not-a-template}')
            end.to raise_error(ValidationError)
          end

          it 'does not skip validation for partial template strings' do
            expect do
              described_class.validate_value('uuid', ColumnSchema.new(column_type: Concerns::PrimitiveTypes::UUID),
                                             '{{incomplete')
            end.to raise_error(ValidationError)
          end
        end
      end
    end
  end
end
