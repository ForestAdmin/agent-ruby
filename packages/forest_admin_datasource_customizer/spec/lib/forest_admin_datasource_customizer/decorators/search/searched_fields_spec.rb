require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Search
      include ForestAdminDatasourceToolkit::Schema
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

      describe SearchCollectionDecorator do
        subject(:decorated) { described_class.new(datasource.get_collection('cards'), datasource) }

        let(:caller) { instance_double(ForestAdminDatasourceToolkit::Components::Caller) }

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

        describe 'when the collection carries a polymorphic relation' do
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
                      'holder_type' => build_column(column_type: 'String'),
                      'holder' => Relations::PolymorphicManyToOneSchema.new(
                        foreign_key: 'holder_id',
                        foreign_key_type_field: 'holder_type',
                        foreign_collections: %w[persons companies],
                        foreign_key_targets: { 'persons' => 'id', 'companies' => 'id' }
                      )
                    }
                  }
                ),
                build_collection(
                  name: 'persons',
                  schema: {
                    fields: {
                      'id' => build_numeric_primary_key,
                      'national_id' => build_column(column_type: 'String', filter_operators: [Operators::I_CONTAINS])
                    }
                  }
                ),
                build_collection(
                  name: 'companies',
                  schema: { fields: { 'id' => build_numeric_primary_key } }
                )
              ]
            )
          end

          before do
            allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(
              instance_double(ForestAdminAgent::Services::LoggerService, log: nil)
            )
          end

          it 'refuses a path crossing it, which the search cannot follow' do
            expect { decorated.replace_search(include_fields: ['holder:national_id']) }
              .to raise_error(
                ForestAdminDatasourceToolkit::Exceptions::ForestException,
                'Unexpected field type PolymorphicManyToOne: cards.holder'
              )
          end

          it 'refuses it named bare, which carries no term to compare' do
            expect { decorated.replace_search(only_fields: ['holder']) }
              .to raise_error(
                ForestAdminDatasourceToolkit::Exceptions::ForestException,
                "Cannot search on 'holder': a PolymorphicManyToOne is not a column"
              )
          end

          it 'refuses excluding a path crossing it, rather than excluding nothing' do
            expect { decorated.replace_search(exclude_fields: ['holder:national_id']) }
              .to raise_error(
                ForestAdminDatasourceToolkit::Exceptions::ForestException,
                'Unexpected field type PolymorphicManyToOne: cards.holder'
              )
          end

          # The request path, not the boot path: an RPC agent resolves nothing from the base facade, so
          # an extended search reaching this relation must not 500 over a Debug line.
          it 'searches on where no logger is resolvable' do
            allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(nil)

            expect(decorated.searched_fields('martin', true).map { |field| field[:path] })
              .to eq(['pan_last4'])
          end

          # Its targets stay out of both, so no footprint entry ever needs the several collections
          # `leaf_collection_names` would answer for a polymorphic leaf.
          it 'keeps its columns out of the footprint and out of what the search reads' do
            decorated.replace_search(include_fields: ['pan_last4'])

            footprint = decorated.searched_fields('martin', true).map { |field| field[:path] }
            refined = decorated.refine_filter(
              caller,
              ForestAdminDatasourceToolkit::Components::Query::Filter.new(
                search: 'martin', search_extended: true
              )
            )

            expect(footprint).to eq(['pan_last4'])
            expect(refined.condition_tree.projection.uniq).to eq(['pan_last4'])
          end
        end

        describe '#refine_filter when the selection leaves no field searchable' do
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
            expect(refined({ exclude_fields: %w[id pan_last4 holder:id holder:national_id] }).condition_tree)
              .to have_attributes(aggregator: 'Or', conditions: [])
          end
        end

        # The fixture above has no searchable column whose name the relation only prefixes, so the
        # `:` boundary in the exclusion cannot be told apart there.
        describe '#replace_search excluding a relation whose name prefixes a column' do
          let(:datasource) do
            build_datasource_with_collections(
              [
                build_collection(
                  name: 'cards',
                  schema: {
                    fields: {
                      'id' => build_numeric_primary_key,
                      'holder_note' => build_column(column_type: 'String',
                                                    filter_operators: [Operators::I_CONTAINS]),
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
                      'national_id' => build_column(column_type: 'String',
                                                    filter_operators: [Operators::I_CONTAINS])
                    }
                  }
                )
              ]
            )
          end

          it 'keeps a sibling column the relation name only prefixes' do
            decorated.replace_search(exclude_fields: ['holder'])

            expect(decorated.searched_fields('martin', true)).to eq(
              [{ path: 'holder_note', collections: ['cards'] }]
            )
          end
        end

        describe '#replace_search with a callable replacer' do
          let(:logger) { instance_double(ForestAdminAgent::Services::LoggerService, log: nil) }

          before { allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(logger) }

          it 'warns at boot that an extended search there is refused where permissions are on' do
            decorated.replace_search(->(value, _extended, _context) { { field: 'pan_last4', value: value } })

            expect(logger).to have_received(:log).with(
              'Warn',
              'An extended search on cards is refused where permissions are enabled: a ' \
              '`replace_search` block names no field, so the agent cannot check what it reads against ' \
              "the caller's permissions. Declaring the search with " \
              '`replace_search(include_fields: [...])` makes it checkable.'
            )
          end

          # The RPC agent runs its own `AgentFactory` subclass, so the base facade's container is never
          # built there and `logger` answers nil.
          it 'installs the block anyway where no logger is resolvable' do
            allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(nil)

            expect { decorated.replace_search(->(value, _extended, _context) { { field: 'pan_last4', value: value } }) }
              .not_to raise_error
            expect(decorated.searched_fields('martin', true)).to be_nil
          end

          it 'says nothing for a field selection, which is checkable' do
            decorated.replace_search(include_fields: ['holder:national_id'])

            expect(logger).not_to have_received(:log)
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

          # `get_field_schema` only requires a to-one relation of the segments it crosses, so a bare
          # relation resolves to a RelationSchema and reached `build_condition`, which asks it for a
          # `column_type` it does not have.
          it 'refuses a bare relation, which carries no term to compare' do
            expect { decorated.replace_search(only_fields: ['holder']) }
              .to raise_error(
                ForestAdminDatasourceToolkit::Exceptions::ForestException,
                "Cannot search on 'holder': a ManyToOne is not a column"
              )
          end

          it 'refuses a column no search term can match, which the defaults already skip' do
            expect { decorated.replace_search(include_fields: ['holder_id']) }
              .to raise_error(
                ForestAdminDatasourceToolkit::Exceptions::ForestException,
                "Cannot search on 'holder_id': its Number column declares no filter operator a search term can use"
              )
          end

          it 'excludes every path through a relation named bare, which no column list could keep up with' do
            decorated.replace_search(exclude_fields: ['holder'])

            expect(decorated.searched_fields('martin', true)).to eq(
              [{ path: 'pan_last4', collections: ['cards'] }]
            )
          end

          # Refusing it would stop the agent booting the day a column named defensively turns
          # unsearchable — the one configuration that only became more correct.
          it 'reports rather than refuses excluding a column the search never reads' do
            logger = instance_double(ForestAdminAgent::Services::LoggerService, log: nil)
            allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(logger)

            expect { decorated.replace_search(exclude_fields: ['holder_id']) }.not_to raise_error
            expect(logger).to have_received(:log).with(
              'Debug',
              "Excluding 'holder_id' from the search on cards changes nothing: the search does not read it"
            )
          end

          it 'still raises on a name that resolves to nothing, which is a typo' do
            expect { decorated.replace_search(exclude_fields: ['holder_ids']) }
              .to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException, /holder_ids/)
          end

          it 'refuses searching and excluding the same path, rather than letting one win silently' do
            expect { decorated.replace_search(include_fields: ['holder:national_id'], exclude_fields: ['holder']) }
              .to raise_error(
                ForestAdminDatasourceToolkit::Exceptions::ForestException,
                "Cannot both search and exclude 'holder:national_id'"
              )
          end

          it 'leaves the previous selection in place when it refuses a new one' do
            decorated.replace_search(only_fields: ['pan_last4'])

            expect { decorated.replace_search(only_fields: ['nope']) }
              .to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException, /nope/)
            expect(decorated.searched_fields('martin', false)).to eq(
              [{ path: 'pan_last4', collections: ['cards'] }]
            )
          end
        end
      end
    end
  end
end
