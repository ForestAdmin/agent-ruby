require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Search
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminDatasourceToolkit::Schema

      describe SearchCollectionDecorator do
        let(:datasource) { ForestAdminDatasourceToolkit::Datasource.new }

        let(:caller) { instance_double(ForestAdminDatasourceToolkit::Components::Caller) }

        before do
          @collection_user = instance_double(
            ForestAdminDatasourceToolkit::Collection,
            name: 'user',
            schema: {
              fields: {
                'address_users' => Relations::OneToManySchema.new(
                  origin_key: 'user_id',
                  origin_key_target: 'id',
                  foreign_collection: 'address_user'
                )
              }
            }
          )

          collection_address_user = instance_double(
            ForestAdminDatasourceToolkit::Collection,
            name: 'address_user',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'address' => Relations::ManyToOneSchema.new(
                  foreign_key: 'address_id',
                  foreign_collection: 'address',
                  foreign_key_target: 'id'
                ),
                'user' => Relations::ManyToOneSchema.new(
                  foreign_key: 'user_id',
                  foreign_collection: 'user',
                  foreign_key_target: 'id'
                )
              }
            }
          )

          collection_address = instance_double(
            ForestAdminDatasourceToolkit::Collection,
            name: 'address',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'location' => ColumnSchema.new(column_type: 'String'),
                'addressable' => Relations::PolymorphicManyToOneSchema.new(
                  foreign_key_type_field: 'addressable_type',
                  foreign_collections: ['user'],
                  foreign_key_targets: { 'user' => 'id' },
                  foreign_key: 'addressable_id'
                )
              }
            }
          )

          datasource.add_collection(@collection_user)
          datasource.add_collection(collection_address_user)
          datasource.add_collection(collection_address)
        end

        context 'when refine_schema' do
          it 'sets the schema searchable' do
            collection = instance_double(ForestAdminDatasourceToolkit::Collection)
            search_collection_decorator = described_class.new(collection, datasource)
            unsearchable_schema = { searchable: false }
            expect(search_collection_decorator.refine_schema(unsearchable_schema)).to eq({ searchable: true })
          end
        end

        context 'when refine_filter' do
          context 'when the collection has polymorphic relation' do
            it 'not search over polymorphic relations with the search extended and show a debug log' do
              logger = instance_double(ForestAdminAgent::Services::LoggerService, log: nil)
              allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(logger)
              filter = Filter.new(search: 'a search value', search_extended: true)
              search_collection_decorator = described_class.new(datasource.get_collection('address'), datasource)
              search_collection_decorator.refine_filter(caller, filter)
              expect(ForestAdminAgent::Facades::Container.logger).to have_received(:log) do |level, message|
                expect(level).to eq('Debug')
                expect(message).to eq(
                  "We're not searching through address.addressable because it's a polymorphic relation. " \
                  "You can override the default search behavior with 'replace_search'. " \
                  'See more: https://docs.forestadmin.com/developer-guide-agents-ruby/agent-customization/search'
                )
              end
            end
          end

          context 'when the search value is null' do
            it 'returns the given filter to return all records' do
              collection = instance_double(ForestAdminDatasourceToolkit::Collection)
              search_collection_decorator = described_class.new(collection, datasource)
              filter = Filter.new(search: nil)
              expect(search_collection_decorator.refine_filter(nil, filter).to_h).to eq(filter.to_h)
            end
          end

          context 'when the given field is a column' do
            it 'adds a condition to return records matching the search value' do
              filter = Filter.new(search: 'a search value')
              search_collection_decorator = described_class.new(@collection_user, datasource)
              refined_filter = search_collection_decorator.refine_filter(caller, filter)

              expect(refined_filter.to_h).to eq(Filter.new.to_h)
            end
          end

          context 'when the collection schema is not searchable' do
            it 'returns the given filter without adding condition' do
              collection = instance_double(
                ForestAdminDatasourceToolkit::Collection,
                name: 'foo',
                schema: {
                  searchable: true
                }
              )
              datasource.add_collection(collection)

              search_collection_decorator = described_class.new(collection, datasource)
              filter = Filter.new(search: 'a text')
              refined_filter = search_collection_decorator.refine_filter(caller, filter)

              expect(refined_filter).to eq(filter)
            end
          end

          context 'when a replacer is provided' do
            it 'is used instead of the default one' do
              collection = instance_double(
                ForestAdminDatasourceToolkit::Collection,
                name: 'foo',
                schema: {
                  fields: { id: ColumnSchema.new(column_type: 'Number', is_primary_key: true) }
                }
              )
              filter = Filter.new(search: 'something')
              decorator = described_class.new(collection, nil)
              decorator.replace_search(proc { |value|
                                         { field: 'id', operator: ConditionTree::Operators::EQUAL, value: value }
                                       })

              refined_filter = decorator.refine_filter(caller, filter)

              expect(refined_filter).to have_attributes(
                condition_tree: have_attributes(field: 'id', operator: ConditionTree::Operators::EQUAL,
                                                value: 'something'),
                search: nil
              )
            end
          end

          context 'when the search is defined and the collection schema is not searchable' do
            context 'when the search is empty' do
              it 'returns the same filter and set search as null' do
                collection = instance_double(
                  ForestAdminDatasourceToolkit::Collection,
                  name: 'foo',
                  schema: {
                    searchable: false
                  }
                )
                filter = Filter.new(search: '     ')

                search_collection_decorator = described_class.new(collection, nil)

                refined_filter = search_collection_decorator.refine_filter(caller, filter)
                expect(refined_filter).to have_attributes(search: nil)
              end
            end

            context 'when the filter contains already conditions' do
              it 'adds its conditions to the filter' do
                collection = instance_double(
                  ForestAdminDatasourceToolkit::Collection,
                  name: 'foo',
                  schema: {
                    searchable: false,
                    fields: {
                      'fieldName' => ColumnSchema.new(
                        column_type: 'String',
                        filter_operators: [ConditionTree::Operators::I_CONTAINS]
                      )
                    }
                  }
                )

                filter = Filter.new(
                  search: 'a text',
                  condition_tree: ConditionTree::Nodes::ConditionTreeBranch.new(
                    'And',
                    [
                      ConditionTree::Nodes::ConditionTreeLeaf.new('aFieldName', ConditionTree::Operators::EQUAL,
                                                                  'fieldValue')
                    ]
                  )
                )

                search_collection_decorator = described_class.new(collection, nil)

                refined_filter = search_collection_decorator.refine_filter(caller, filter)
                expect(refined_filter).to have_attributes(
                  search: nil,
                  condition_tree: have_attributes(
                    aggregator: 'And',
                    conditions: [
                      have_attributes(field: 'aFieldName', operator: ConditionTree::Operators::EQUAL,
                                      value: 'fieldValue'),
                      have_attributes(field: 'fieldName', operator: ConditionTree::Operators::I_CONTAINS,
                                      value: 'a text')
                    ]
                  )
                )
              end
            end

            context 'when the search is a string and the column type is a string' do
              it 'returns filter with "contains" condition and "or" aggregator' do
                collection = instance_double(
                  ForestAdminDatasourceToolkit::Collection,
                  name: 'foo',
                  schema: {
                    searchable: false,
                    fields: {
                      'fieldName' => ColumnSchema.new(
                        column_type: 'String',
                        filter_operators: [ConditionTree::Operators::I_CONTAINS, ConditionTree::Operators::CONTAINS]
                      )
                    }
                  }
                )

                filter = Filter.new(search: 'a text')

                search_collection_decorator = described_class.new(collection, nil)

                refined_filter = search_collection_decorator.refine_filter(caller, filter)
                expect(refined_filter).to have_attributes(
                  search: nil,
                  condition_tree: have_attributes(field: 'fieldName', operator: ConditionTree::Operators::CONTAINS,
                                                  value: 'a text')
                )
              end
            end

            context 'when searching on a string that only supports Equal' do
              it 'returns filter with "equal" condition' do
                collection = instance_double(
                  ForestAdminDatasourceToolkit::Collection,
                  name: 'foo',
                  schema: {
                    searchable: false,
                    fields: {
                      'fieldName' => ColumnSchema.new(
                        column_type: 'String',
                        filter_operators: [ConditionTree::Operators::EQUAL]
                      )
                    }
                  }
                )

                filter = Filter.new(search: 'a text')

                search_collection_decorator = described_class.new(collection, nil)

                refined_filter = search_collection_decorator.refine_filter(caller, filter)
                expect(refined_filter.search).to be_nil
                expect(refined_filter.condition_tree.to_h).to eq(
                  ConditionTree::Nodes::ConditionTreeLeaf.new('fieldName', ConditionTree::Operators::EQUAL, 'a text').to_h
                )
              end
            end

            context 'when search is a case insensitive string and both operators are supported' do
              it 'returns filter with "contains" condition and "or" aggregator' do
                collection = instance_double(
                  ForestAdminDatasourceToolkit::Collection,
                  name: 'foo',
                  schema: {
                    searchable: false,
                    fields: {
                      'fieldName' => ColumnSchema.new(
                        column_type: 'String',
                        filter_operators: [ConditionTree::Operators::I_CONTAINS, ConditionTree::Operators::CONTAINS]
                      )
                    }
                  }
                )

                filter = Filter.new(search: '@#*$(@#*$(23423423')

                search_collection_decorator = described_class.new(collection, nil)

                refined_filter = search_collection_decorator.refine_filter(caller, filter)
                expect(refined_filter).to have_attributes(
                  search: nil,
                  condition_tree: have_attributes(field: 'fieldName', operator: ConditionTree::Operators::CONTAINS,
                                                  value: '@#*$(@#*$(23423423')
                )
              end
            end

            context 'when the search is an uuid and the column type is an uuid' do
              it 'returns filter with "equal" condition and "or" aggregator' do
                collection = instance_double(
                  ForestAdminDatasourceToolkit::Collection,
                  name: 'foo',
                  schema: {
                    searchable: false,
                    fields: {
                      'fieldName' => ColumnSchema.new(
                        column_type: 'Uuid',
                        filter_operators: [ConditionTree::Operators::EQUAL]
                      )
                    }
                  }
                )

                filter = Filter.new(search: '2d162303-78bf-599e-b197-93590ac3d315')

                search_collection_decorator = described_class.new(collection, nil)

                refined_filter = search_collection_decorator.refine_filter(caller, filter)
                expect(refined_filter).to have_attributes(
                  search: nil,
                  condition_tree: have_attributes(field: 'fieldName', operator: ConditionTree::Operators::EQUAL,
                                                  value: '2d162303-78bf-599e-b197-93590ac3d315')
                )
              end
            end

            context 'when the search is a number and the column type is a number' do
              it 'returns "equal" condition, "or" aggregator and cast value to Number' do
                collection = instance_double(
                  ForestAdminDatasourceToolkit::Collection,
                  name: 'foo',
                  schema: {
                    searchable: false,
                    fields: {
                      'fieldName' => ColumnSchema.new(
                        column_type: 'Number',
                        filter_operators: [ConditionTree::Operators::EQUAL]
                      ),
                      'fieldName2' => ColumnSchema.new(
                        column_type: 'String',
                        filter_operators: [ConditionTree::Operators::I_CONTAINS]
                      )
                    }
                  }
                )

                filter = Filter.new(search: '1584')

                search_collection_decorator = described_class.new(collection, nil)

                refined_filter = search_collection_decorator.refine_filter(caller, filter)
                expect(refined_filter).to have_attributes(
                  search: nil,
                  condition_tree: have_attributes(
                    aggregator: 'Or',
                    conditions: [
                      have_attributes(field: 'fieldName', operator: ConditionTree::Operators::EQUAL, value: 1584),
                      have_attributes(field: 'fieldName2', operator: ConditionTree::Operators::I_CONTAINS,
                                      value: '1584')
                    ]
                  )
                )
              end
            end

            context 'when the search is an string and the column type is an enum' do
              it 'returns filter with "equal" condition and "or" aggregator' do
                collection = instance_double(
                  ForestAdminDatasourceToolkit::Collection,
                  name: 'foo',
                  schema: {
                    searchable: false,
                    fields: {
                      'fieldName' => ColumnSchema.new(
                        column_type: 'Enum',
                        enum_values: ['AnEnUmVaLue'],
                        filter_operators: [ConditionTree::Operators::EQUAL]
                      )
                    }
                  }
                )

                filter = Filter.new(search: 'anenumvalue')

                search_collection_decorator = described_class.new(collection, nil)

                refined_filter = search_collection_decorator.refine_filter(caller, filter)
                expect(refined_filter.search).to be_nil
                expect(refined_filter.condition_tree.to_h).to eq(
                  ConditionTree::Nodes::ConditionTreeLeaf.new('fieldName', ConditionTree::Operators::EQUAL, 'AnEnUmVaLue').to_h
                )
              end

              context 'when the search value does not match any enum' do
                it 'adds a condition to not return record if it is the only one filter' do
                  collection = instance_double(
                    ForestAdminDatasourceToolkit::Collection,
                    name: 'foo',
                    schema: {
                      searchable: false,
                      fields: {
                        'fieldName' => ColumnSchema.new(
                          column_type: 'Enum',
                          enum_values: ['AEnumValue'],
                          filter_operators: [ConditionTree::Operators::EQUAL]
                        )
                      }
                    }
                  )

                  filter = Filter.new(search: 'NotExistEnum')

                  search_collection_decorator = described_class.new(collection, nil)

                  refined_filter = search_collection_decorator.refine_filter(caller, filter)
                  expect(refined_filter).to have_attributes(
                    search: nil,
                    condition_tree: have_attributes(aggregator: 'Or', conditions: [])
                  )
                end
              end

              context 'when the enum values are not defined' do
                it 'adds a condition to not return record if it is the only one filter' do
                  collection = instance_double(
                    ForestAdminDatasourceToolkit::Collection,
                    name: 'foo',
                    schema: {
                      searchable: false,
                      fields: {
                        'fieldName' => ColumnSchema.new(
                          column_type: 'Enum'
                          # enum values is not defined
                        )
                      }
                    }
                  )

                  filter = Filter.new(search: 'NotExistEnum')

                  search_collection_decorator = described_class.new(collection, nil)

                  refined_filter = search_collection_decorator.refine_filter(caller, filter)
                  expect(refined_filter).to have_attributes(
                    search: nil,
                    condition_tree: have_attributes(aggregator: 'Or', conditions: [])
                  )
                end
              end

              context 'when the column type is not searchable' do
                it 'adds a condition to not return record if it is the only one filter' do
                  collection = instance_double(
                    ForestAdminDatasourceToolkit::Collection,
                    name: 'foo',
                    schema: {
                      searchable: false,
                      fields: {
                        'fieldName' => ColumnSchema.new(
                          column_type: 'Boolean'
                        )
                      }
                    }
                  )

                  filter = Filter.new(search: '1584')

                  search_collection_decorator = described_class.new(collection, nil)

                  refined_filter = search_collection_decorator.refine_filter(caller, filter)
                  expect(refined_filter).to have_attributes(
                    search: nil,
                    condition_tree: have_attributes(aggregator: 'Or', conditions: [])
                  )
                end
              end
            end

            context 'when there are several fields' do
              it 'returns all the number fields when a number is researched' do
                collection = instance_double(
                  ForestAdminDatasourceToolkit::Collection,
                  name: 'foo',
                  schema: {
                    searchable: false,
                    fields: {
                      'numberField1' => ColumnSchema.new(
                        column_type: 'Number',
                        filter_operators: [ConditionTree::Operators::EQUAL]
                      ),
                      'numberField2' => ColumnSchema.new(
                        column_type: 'Number',
                        filter_operators: [ConditionTree::Operators::EQUAL]
                      ),
                      'fieldNotReturned' => ColumnSchema.new(column_type: 'Uuid')
                    }
                  }
                )

                filter = Filter.new(search: '1584')

                search_collection_decorator = described_class.new(collection, nil)

                refined_filter = search_collection_decorator.refine_filter(caller, filter)
                expect(refined_filter).to have_attributes(
                  search: nil,
                  condition_tree: have_attributes(
                    aggregator: 'Or',
                    conditions: [
                      have_attributes(field: 'numberField1', operator: ConditionTree::Operators::EQUAL, value: 1584),
                      have_attributes(field: 'numberField2', operator: ConditionTree::Operators::EQUAL, value: 1584)
                    ]
                  )
                )
              end

              context 'when it is a deep search with relation fields' do
                it 'returns all the uuid fields when uuid is researched' do
                  collection_book = ForestAdminDatasourceToolkit::Collection.new(
                    datasource,
                    'book'
                  )
                  collection_book.add_fields(
                    {
                      'id' => ColumnSchema.new(
                        column_type: 'Uuid',
                        is_primary_key: true,
                        filter_operators: [ConditionTree::Operators::EQUAL]
                      ),
                      'my_persons' => Relations::OneToOneSchema.new(
                        origin_key: 'person_id',
                        origin_key_target: 'id',
                        foreign_collection: 'person'
                      ),
                      'my_book_persons' => Relations::ManyToOneSchema.new(
                        foreign_key: 'book_id',
                        foreign_key_target: 'id',
                        foreign_collection: 'book_person'
                      )
                    }
                  )

                  collection_book_persons = ForestAdminDatasourceToolkit::Collection.new(
                    datasource,
                    'book_person'
                  )
                  collection_book_persons.add_fields(
                    {
                      'book_id' => ColumnSchema.new(
                        column_type: 'Uuid',
                        is_primary_key: true,
                        filter_operators: [ConditionTree::Operators::EQUAL]
                      ),
                      'person_id' => ColumnSchema.new(
                        column_type: 'Uuid',
                        is_primary_key: true,
                        filter_operators: [ConditionTree::Operators::EQUAL]
                      )
                    }
                  )

                  collection_persons = ForestAdminDatasourceToolkit::Collection.new(
                    datasource,
                    'person'
                  )
                  collection_persons.add_fields(
                    {
                      'id' => ColumnSchema.new(
                        column_type: 'Uuid',
                        is_primary_key: true,
                        filter_operators: [ConditionTree::Operators::EQUAL]
                      )
                    }
                  )

                  datasource.add_collection(collection_book)
                  datasource.add_collection(collection_book_persons)
                  datasource.add_collection(collection_persons)

                  filter = Filter.new(
                    search_extended: true,
                    search: '2d162303-78bf-599e-b197-93590ac3d315'
                  )

                  search_collection_decorator = described_class.new(collection_book, datasource)

                  refined_filter = search_collection_decorator.refine_filter(caller, filter)
                  expect(refined_filter).to have_attributes(
                    search_extended: true,
                    search: nil,
                    condition_tree: have_attributes(
                      aggregator: 'Or',
                      conditions: [
                        have_attributes(field: 'id', operator: ConditionTree::Operators::EQUAL,
                                        value: '2d162303-78bf-599e-b197-93590ac3d315'),
                        have_attributes(field: 'my_persons:id', operator: ConditionTree::Operators::EQUAL,
                                        value: '2d162303-78bf-599e-b197-93590ac3d315'),
                        have_attributes(field: 'my_book_persons:book_id', operator: ConditionTree::Operators::EQUAL,
                                        value: '2d162303-78bf-599e-b197-93590ac3d315'),
                        have_attributes(field: 'my_book_persons:person_id', operator: ConditionTree::Operators::EQUAL,
                                        value: '2d162303-78bf-599e-b197-93590ac3d315')
                      ]
                    )
                  )
                end
              end
            end
          end
        end
      end
    end
  end
end
