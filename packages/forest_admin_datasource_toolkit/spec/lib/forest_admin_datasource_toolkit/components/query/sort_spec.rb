require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Components
    module Query
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Schema
      include ForestAdminDatasourceToolkit::Components::Query::SortUtils
      describe Sort do
        let(:sort) { described_class.new([{ field: 'column1', ascending: true }, { field: 'column2', ascending: false }]) }

        it 'projection should work' do
          expect(sort.projection).to eq(['column1', 'column2'])
        end

        it('apply should sort records') do
          records = [
            { column1: 2, column2: 2 },
            { column1: 1, column2: 1 },
            { column1: 1, column2: 1 },
            { column1: 1, column2: 2 },
            { column1: 2, column2: 1 }
          ]
          expect(sort.apply(records)).to eq([
                                              { column1: 1, column2: 2 },
                                              { column1: 1, column2: 1 },
                                              { column1: 1, column2: 1 },
                                              { column1: 2, column2: 2 },
                                              { column1: 2, column2: 1 }
                                            ])
        end

        context 'when replace_clauses is called' do
          it 'works when returning a single clause' do
            expect(sort.replace_clauses { |clause| { field: clause[:field], ascending: !clause[:ascending] } }).to eq([
                                                                                                                        { field: 'column1', ascending: false },
                                                                                                                        { field: 'column2', ascending: true }
                                                                                                                      ])
          end
        end

        context 'when nest is called' do
          it 'does nothing with nil' do
            expect(sort.nest(nil)).to eq(sort)
          end

          it 'works with a prefix' do
            expect(sort.nest('prefix')).to eq([
                                                { field: 'prefix:column1', ascending: true },
                                                { field: 'prefix:column2', ascending: false }
                                              ])
          end
        end

        context 'when unnest is called' do
          it 'sorts' do
            expect(sort.nest('prefix').unnest).to eq(sort)
          end

          it 'fails when no common prefix exists' do
            expect { sort.unnest }.to raise_error('Cannot unnest sort.')
          end
        end
      end
    end
  end
end
