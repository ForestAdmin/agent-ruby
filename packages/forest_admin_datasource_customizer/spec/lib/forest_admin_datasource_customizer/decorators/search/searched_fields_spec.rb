require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Search
      include ForestAdminDatasourceToolkit::Schema
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

      describe SearchCollectionDecorator do
        subject(:decorated) { described_class.new(datasource.get_collection('cards'), datasource) }

        let(:datasource) do
          build_datasource_with_collections(
            [
              build_collection(
                name: 'cards',
                schema: {
                  fields: {
                    'id' => build_numeric_primary_key,
                    'pan_last4' => build_column(column_type: 'String', filter_operators: [Operators::I_CONTAINS]),
                    'holder_id' => build_column(column_type: 'Number'),
                    'holder' => build_many_to_one(foreign_collection: 'holders', foreign_key: 'holder_id')
                  }
                }
              ),
              build_collection(
                name: 'holders',
                schema: {
                  fields: {
                    'id' => build_numeric_primary_key,
                    'national_id' => build_column(column_type: 'String', filter_operators: [Operators::I_CONTAINS])
                  }
                }
              )
            ]
          )
        end

        describe '#searched_fields' do
          it 'reports the columns of the collection itself when the search is not extended' do
            expect(decorated.searched_fields('martin', false)).to contain_exactly(
              { path: 'id', collections: ['cards'] },
              { path: 'pan_last4', collections: ['cards'] }
            )
          end

          it 'reports the collection a relation column belongs to when the search is extended' do
            expect(decorated.searched_fields('martin', true)).to contain_exactly(
              { path: 'id', collections: ['cards'] },
              { path: 'pan_last4', collections: ['cards'] },
              { path: 'holder:id', collections: ['holders'] },
              { path: 'holder:national_id', collections: ['holders'] }
            )
          end

          # Reading it as "reaches nothing" would let a replaced search through unchecked.
          it 'answers nothing it can be sure of once a replacer chooses the fields' do
            decorated.replace_search(->(search, _extended, _context) { { field: 'id', operator: 'equal', value: search } })

            expect(decorated.searched_fields('martin', true)).to be_nil
          end

          it 'answers nothing it can be sure of when the datasource searches natively' do
            child = datasource.get_collection('cards')
            allow(child).to receive(:schema).and_return(child.schema.merge(searchable: true))

            expect(described_class.new(child, datasource).searched_fields('martin', true)).to be_nil
          end
        end
      end
    end
  end
end
