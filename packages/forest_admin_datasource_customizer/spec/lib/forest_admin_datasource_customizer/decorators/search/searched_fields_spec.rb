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
              { path: 'pan_last4', collections: ['cards'] }
            )
          end

          it 'reports the collection a relation column belongs to when the search is extended' do
            expect(decorated.searched_fields('martin', true)).to contain_exactly(
              { path: 'pan_last4', collections: ['cards'] },
              { path: 'holder:national_id', collections: ['holders'] }
            )
          end

          it 'leaves out a column the term cannot match, which the search builds no condition for' do
            expect(decorated.searched_fields('martin', true).map { |field| field[:path] })
              .not_to include('id', 'holder:id')
          end

          it 'reports a numeric column once the term is a number the search will compare it to' do
            expect(decorated.searched_fields('42', true)).to contain_exactly(
              { path: 'id', collections: ['cards'] },
              { path: 'pan_last4', collections: ['cards'] },
              { path: 'holder:id', collections: ['holders'] },
              { path: 'holder:national_id', collections: ['holders'] }
            )
          end

          it 'reaches nothing for a search the stack discards as insignificant' do
            expect(decorated.searched_fields('  ', true)).to eq([])
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

        describe '#searched_fields when a field selection narrows the default search' do
          it 'answers the footprint instead of refusing to tell' do
            decorated.replace_search(exclude_fields: ['pan_last4'])

            expect(decorated.searched_fields('martin', true)).to contain_exactly(
              { path: 'holder:national_id', collections: ['holders'] }
            )
          end

          it 'reports an included relation path on a plain search too, not only an extended one' do
            decorated.replace_search(include_fields: ['holder:national_id'])

            expect(decorated.searched_fields('martin', false)).to contain_exactly(
              { path: 'pan_last4', collections: ['cards'] },
              { path: 'holder:national_id', collections: ['holders'] }
            )
          end

          it 'reports only the replaced set once only_fields is given' do
            decorated.replace_search(only_fields: ['holder:national_id'])

            expect(decorated.searched_fields('martin', true)).to eq(
              [{ path: 'holder:national_id', collections: ['holders'] }]
            )
          end

          it 'reports an included path once, where it overlaps a default field' do
            decorated.replace_search(include_fields: ['pan_last4'])

            expect(decorated.searched_fields('martin', false).map { |field| field[:path] })
              .to eq(['pan_last4'])
          end

          it 'answers the footprint even when the datasource searches natively, which it replaces' do
            child = datasource.get_collection('cards')
            allow(child).to receive(:schema).and_return(child.schema.merge(searchable: true))
            decorator = described_class.new(child, datasource)
            decorator.replace_search(only_fields: ['pan_last4'])

            expect(decorator.searched_fields('martin', true)).to eq(
              [{ path: 'pan_last4', collections: ['cards'] }]
            )
          end

          it 'still answers nothing it can be sure of when a callable chooses the fields' do
            decorated.replace_search(->(search, _extended, _context) { { field: 'id', operator: 'equal', value: search } })

            expect(decorated.searched_fields('martin', true)).to be_nil
          end
        end

        # The invariant the permission check rests on: a path the search reads without appearing in
        # the footprint is a column read unchecked.
        describe '#searched_fields against what the search actually reads' do
          let(:caller) { instance_double(ForestAdminDatasourceToolkit::Components::Caller) }

          def paths_read(selection, search: 'martin', extended: true)
            decorated.replace_search(**selection)
            refined = decorated.refine_filter(
              caller,
              ForestAdminDatasourceToolkit::Components::Query::Filter.new(
                search: search, search_extended: extended
              )
            )

            refined.condition_tree.projection.uniq
          end

          it 'covers every path an included relation path makes the search read' do
            read = paths_read({ include_fields: ['holder:national_id'] })
            footprint = decorated.searched_fields('martin', true).map { |field| field[:path] }

            expect(read).to include('holder:national_id')
            expect(footprint).to include(*read)
          end

          it 'covers every path the search reads once exclude_fields dropped one' do
            read = paths_read({ exclude_fields: ['pan_last4'] })
            footprint = decorated.searched_fields('martin', true).map { |field| field[:path] }

            expect(read).not_to include('pan_last4')
            expect(read).to include('holder:national_id')
            expect(footprint).to include(*read)
          end

          it 'covers every path the search reads once only_fields replaced the set' do
            read = paths_read({ only_fields: ['holder:national_id'] })
            footprint = decorated.searched_fields('martin', true).map { |field| field[:path] }

            expect(read).to eq(['holder:national_id'])
            expect(footprint).to include(*read)
          end

          it 'reads nothing outside the footprint for a numeric term, which matches more columns' do
            read = paths_read({ include_fields: ['holder:national_id'] }, search: '42')
            footprint = decorated.searched_fields('42', true).map { |field| field[:path] }

            expect(read).to include('id', 'holder:id')
            expect(footprint).to include(*read)
          end
        end

        describe '#refine_filter when the selection leaves no field searchable' do
          let(:caller) { instance_double(ForestAdminDatasourceToolkit::Components::Caller) }

          def refined(selection)
            decorated.replace_search(selection)
            decorated.refine_filter(
              caller,
              ForestAdminDatasourceToolkit::Components::Query::Filter.new(search: 'martin')
            )
          end

          # An empty union is nil, and `intersect` drops a nil: the search would carry no condition
          # at all and the request would answer every row instead of none.
          it 'matches nothing rather than everything once only_fields is empty' do
            expect(refined({ only_fields: [] }).condition_tree)
              .to have_attributes(aggregator: 'Or', conditions: [])
          end

          it 'matches nothing rather than everything once every searchable field is excluded' do
            expect(refined({ exclude_fields: %w[id pan_last4 holder_id holder:id holder:national_id] }).condition_tree)
              .to have_attributes(aggregator: 'Or', conditions: [])
          end
        end

        describe '#replace_search with an unresolvable field selection' do
          it 'names the field it cannot resolve rather than searching nothing for good' do
            expect { decorated.replace_search(only_fields: ['pan_last_four']) }
              .to raise_error(
                ForestAdminDatasourceToolkit::Exceptions::ForestException,
                /Column not found cards.pan_last_four/
              )
          end

          # The list is written by the developer, so a name that names nothing is a mistake to
          # report rather than one to guess at.
          it 'refuses a name spelt in another case rather than resolving it fuzzily' do
            expect { decorated.replace_search(include_fields: ['panLast4']) }
              .to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException, /panLast4/)
          end

          it 'accepts a symbol, which resolves to the same column as the string' do
            decorated.replace_search(only_fields: [:pan_last4])

            expect(decorated.searched_fields('martin', false)).to eq(
              [{ path: 'pan_last4', collections: ['cards'] }]
            )
          end

          it 'checks the excluded names too, which would otherwise exclude nothing' do
            expect { decorated.replace_search(exclude_fields: ['nope']) }
              .to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException, /nope/)
          end

          it 'refuses a path reaching through a relation the search cannot follow' do
            expect { decorated.replace_search(include_fields: ['holder:nope']) }
              .to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException, /nope/)
          end
        end
      end
    end
  end
end
