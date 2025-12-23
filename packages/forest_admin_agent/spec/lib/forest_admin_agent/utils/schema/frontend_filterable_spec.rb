require 'spec_helper'

module ForestAdminAgent
  module Utils
    module Schema
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

      describe FrontendFilterable do
        subject(:frontend_filterable) { described_class }

        it 'returns false with no operators' do
          expect(frontend_filterable).not_to be_filterable([])
        end

        it 'returns true with only the relevant operators' do
          expect(frontend_filterable).to be_filterable([
                                                         Operators::EQUAL,
                                                         Operators::NOT_EQUAL,
                                                         Operators::PRESENT,
                                                         Operators::BLANK,
                                                         Operators::IN,
                                                         Operators::STARTS_WITH,
                                                         Operators::ENDS_WITH,
                                                         Operators::CONTAINS,
                                                         Operators::NOT_CONTAINS
                                                       ])
        end

        it 'returns true with includeAll' do
          expect(frontend_filterable).to be_filterable([Operators::INCLUDES_ALL])
        end

        describe '.sort_operators' do
          it 'sorts operators alphabetically' do
            unsorted = [Operators::PRESENT, Operators::EQUAL, Operators::BLANK, Operators::IN]
            sorted = frontend_filterable.sort_operators(unsorted)
            expect(sorted).to eq([Operators::BLANK, Operators::EQUAL, Operators::IN, Operators::PRESENT])
          end

          it 'returns nil if operators is nil' do
            expect(frontend_filterable.sort_operators(nil)).to be_nil
          end

          it 'returns the input if operators is not an array' do
            expect(frontend_filterable.sort_operators('not_an_array')).to eq('not_an_array')
          end

          it 'handles empty array' do
            expect(frontend_filterable.sort_operators([])).to eq([])
          end
        end
      end
    end
  end
end
