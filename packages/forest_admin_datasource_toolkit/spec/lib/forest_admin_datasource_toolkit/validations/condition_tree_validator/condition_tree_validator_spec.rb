require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Validations
    include ForestAdminDatasourceToolkit::Schema
    include ForestAdminDatasourceToolkit::Exceptions
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes

    describe ConditionTreeValidator do
      describe 'validate' do
        context 'with an invalid type' do
          it 'raise an error' do
            collection = Collection.new(Datasource.new, 'foo')
            condition_tree = []

            expect do
              described_class.validate(condition_tree, collection)
            end.to raise_error(Exceptions::ValidationError, 'Unexpected condition tree type')
          end
        end

        context 'with an invalid aggregator on branch' do
          it 'raise an error' do
            collection = Collection.new(Datasource.new, 'foo')
            condition_tree = ConditionTreeBranch.new('and', []) # should be 'And'

            expect do
              described_class.validate(condition_tree, collection)
            end.to raise_error(
              Exceptions::ValidationError,
              "The given aggregator 'and' is not supported. The supported values are: ['Or', 'And']"
            )
          end
        end

        context 'with an invalid conditions on branch' do
          it 'raise an error' do
            collection = Collection.new(Datasource.new, 'foo')
            condition_tree = ConditionTreeBranch.new('And', 'nil')

            expect do
              described_class.validate(condition_tree, collection)
            end.to raise_error(
              Exceptions::ValidationError,
              "The given conditions 'nil' were expected to be an array"
            )
          end
        end

        context 'when the field(s) does not exist in the schema' do
          it 'raise an error' do
            collection = build_collection(
              {
                schema: { fields: { target: ColumnSchema.new(column_type: 'String') } }
              }
            )

            condition_tree = ConditionTreeLeaf.new('fieldDoesNotExistInSchema', Operators::EQUAL, 'targetValue')

            expect do
              described_class.validate(condition_tree, collection)
            end.to raise_error(
              Exceptions::ForestException,
              'Column not found collection.fieldDoesNotExistInSchema'
            )
          end

          describe 'when there are relations in the datasource' do
            it 'not raise an error' do
              datasource = build_datasource_with_collections(
                [
                  build_collection({
                                     name: 'book',
                                     schema: {
                                       fields: {
                                         'id' => ColumnSchema.new(column_type: 'String'),
                                         'author' => Relations::ManyToOneSchema.new(
                                           foreign_key: 'author_id',
                                           foreign_collection: 'person',
                                           foreign_key_target: 'id'
                                         ),
                                         'author_id' => ColumnSchema.new(column_type: 'String')
                                       }
                                     }
                                   }),
                  build_collection({
                                     name: 'person',
                                     schema: {
                                       fields: {
                                         'id' => ColumnSchema.new(column_type: 'String', filter_operators: [Operators::EQUAL])
                                       }
                                     }
                                   })
                ]
              )

              condition_tree = ConditionTreeLeaf.new('author:id', Operators::EQUAL, '1')

              expect(described_class.validate(condition_tree, datasource.get_collection('book'))).to be_nil
            end
          end

          describe 'when there are several fields' do
            it 'raise an error when a field does not exist' do
              collection = build_collection({
                                              schema: {
                                                fields: {
                                                  'target' => ColumnSchema.new(column_type: 'String', filter_operators: [Operators::EQUAL])
                                                }
                                              }
                                            })

              condition_tree = ConditionTreeBranch.new(
                'And',
                [
                  ConditionTreeLeaf.new('target', Operators::EQUAL, 'targetValue'),
                  ConditionTreeLeaf.new('fieldDoesNotExistInSchema', Operators::EQUAL, 'targetValue')
                ]
              )

              expect do
                described_class.validate(condition_tree, collection)
              end.to raise_error(
                Exceptions::ForestException,
                'Column not found collection.fieldDoesNotExistInSchema'
              )
            end
          end
        end

        context 'when the field(s) exist' do
          it 'not raise an error' do
            collection = build_collection({
                                            schema: {
                                              fields: {
                                                'target' => ColumnSchema.new(column_type: 'String', filter_operators: [Operators::EQUAL])
                                              }
                                            }
                                          })

            condition_tree = ConditionTreeLeaf.new('target', Operators::EQUAL, 'targetValue')

            expect(described_class.validate(condition_tree, collection)).to be_nil
          end

          describe 'when there are several fields' do
            it 'not raise an error' do
              collection = build_collection({
                                              schema: {
                                                fields: {
                                                  'target' => ColumnSchema.new(column_type: 'String', filter_operators: [Operators::EQUAL])
                                                }
                                              }
                                            })

              condition_tree = ConditionTreeBranch.new(
                'Or',
                [
                  ConditionTreeLeaf.new('target', Operators::EQUAL, 'targetValue'),
                  ConditionTreeLeaf.new('target', Operators::EQUAL, 'anotherTargetValue')
                ]
              )

              expect(described_class.validate(condition_tree, collection)).to be_nil
            end
          end
        end

        context 'when the column has no operator' do
          it 'raises that the column is not filterable' do
            collection = build_collection({ schema: { fields: { 'target' => ColumnSchema.new(column_type: 'String') } } })
            condition_tree = ConditionTreeLeaf.new('target', Operators::EQUAL, 'value')

            expect { described_class.validate(condition_tree, collection) }.to raise_error(
              Exceptions::ValidationError,
              "The given operator 'equal' is not supported by the column: 'target'. The column is not filterable"
            )
          end
        end

        context 'when the column does not support the operator' do
          it 'raises with the allowed operators' do
            collection = build_collection(
              { schema: { fields: { 'target' => ColumnSchema.new(column_type: 'String', filter_operators: [Operators::EQUAL, Operators::IN]) } } }
            )
            condition_tree = ConditionTreeLeaf.new('target', Operators::CONTAINS, 'value')

            expect { described_class.validate(condition_tree, collection) }.to raise_error(
              Exceptions::ValidationError,
              "The given operator 'contains' is not supported by the column: 'target'. The allowed types are: equal,in"
            )
          end
        end

        context 'when the field has an operator incompatible with the schema type' do
          it 'raise an error' do
            collection = build_collection({
                                            schema: {
                                              fields: {
                                                'target' => ColumnSchema.new(column_type: 'Number', filter_operators: [Operators::CONTAINS])
                                              }
                                            }
                                          })
            condition_tree = ConditionTreeLeaf.new('target', Operators::CONTAINS, 'subValue')

            expect do
              described_class.validate(condition_tree, collection)
            end.to raise_error(
              Exceptions::ValidationError,
              "The given operator 'contains' is not allowed with the columnType schema: 'Number'. " \
              'The allowed types are: ' \
              '[blank,equal,missing,not_equal,present,in,not_in,includes_all,greater_than,less_than,greater_than_or_equal,less_than_or_equal]'
            )
          end
        end

        context 'when the operator is incompatible with the given value' do
          it 'raise an error' do
            collection = build_collection({
                                            schema: {
                                              fields: {
                                                'target' => ColumnSchema.new(column_type: 'Number', filter_operators: [Operators::GREATER_THAN])
                                              }
                                            }
                                          })
            condition_tree = ConditionTreeLeaf.new('target', Operators::GREATER_THAN, nil)

            expect do
              described_class.validate(condition_tree, collection)
            end.to raise_error(
              Exceptions::ValidationError,
              "The given value has a wrong type for 'target': .\n Expects [\"String\", \"Number\", \"Date\", \"Timeonly\", \"Dateonly\"]"
            )
          end
        end

        context 'when the value is not compatible with the column type' do
          it 'raise an error' do
            collection = build_collection({
                                            schema: {
                                              fields: {
                                                'target' => ColumnSchema.new(column_type: 'String', filter_operators: [Operators::IN])
                                              }
                                            }
                                          })
            condition_tree = ConditionTreeLeaf.new('target', Operators::IN, [1, 2, 3])

            expect do
              described_class.validate(condition_tree, collection)
            end.to raise_error(
              Exceptions::ValidationError,
              "The given value has a wrong type for 'target': 1.\n Expects [\"String\", nil]"
            )
          end
        end

        context 'when the condition goes through a relation that is not filterable' do
          let(:datasource) do
            build_datasource_with_collections(
              [
                build_collection(
                  name: 'book',
                  schema: {
                    fields: {
                      'id' => ColumnSchema.new(column_type: 'String', is_primary_key: true),
                      'author_id' => ColumnSchema.new(column_type: 'String', filter_operators: [Operators::EQUAL]),
                      'author' => Relations::ManyToOneSchema.new(
                        foreign_key: 'author_id',
                        foreign_collection: 'person',
                        foreign_key_target: 'id',
                        is_filterable: false
                      ),
                      'editor' => Relations::ManyToOneSchema.new(
                        foreign_key: 'author_id',
                        foreign_collection: 'person',
                        foreign_key_target: 'id'
                      )
                    }
                  }
                ),
                build_collection(
                  name: 'person',
                  schema: {
                    fields: {
                      'id' => ColumnSchema.new(column_type: 'String', filter_operators: [Operators::EQUAL]),
                      'passport' => Relations::OneToOneSchema.new(
                        origin_key: 'person_id',
                        origin_key_target: 'id',
                        foreign_collection: 'passport',
                        is_filterable: false
                      )
                    }
                  }
                ),
                build_collection(
                  name: 'passport',
                  schema: {
                    fields: {
                      'person_id' => ColumnSchema.new(column_type: 'String', filter_operators: [Operators::EQUAL])
                    }
                  }
                )
              ]
            )
          end
          let(:book) { datasource.get_collection('book') }

          it 'raises on a many to one' do
            condition_tree = ConditionTreeLeaf.new('author:id', Operators::EQUAL, '1')

            expect { described_class.validate(condition_tree, book) }.to raise_error(
              Exceptions::ValidationError, "The relation 'book.author' is not filterable"
            )
          end

          it 'raises on a one to one reached through a filterable relation' do
            condition_tree = ConditionTreeLeaf.new('editor:passport:person_id', Operators::EQUAL, '1')

            expect { described_class.validate(condition_tree, book) }.to raise_error(
              Exceptions::ValidationError, "The relation 'person.passport' is not filterable"
            )
          end

          it 'raises when the leaf is nested in a branch' do
            condition_tree = ConditionTreeBranch.new(
              'Or',
              [
                ConditionTreeLeaf.new('editor:id', Operators::EQUAL, '1'),
                ConditionTreeLeaf.new('author:id', Operators::EQUAL, '1')
              ]
            )

            expect { described_class.validate(condition_tree, book) }.to raise_error(
              Exceptions::ValidationError, "The relation 'book.author' is not filterable"
            )
          end

          it 'still accepts the foreign key column of the relation' do
            condition_tree = ConditionTreeLeaf.new('author_id', Operators::EQUAL, '1')

            expect(described_class.validate(condition_tree, book)).to be_nil
          end
        end
      end
    end
  end
end
