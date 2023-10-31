require 'spec_helper'

module ForestAdminAgent
  module Utils
    module Schema
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

      describe FrontendFilterable do
        subject(:frontend_filterable) { described_class }

        it 'returns false with no operators' do
          expect(frontend_filterable).not_to be_filterable('String')
        end

        it 'returns true with only the relevant operators' do
          expect(frontend_filterable).to be_filterable('String', [
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

        it 'returns true with all operators' do
          expect(frontend_filterable).filterable?('String', Operators.all)
        end

        it 'returns false with array and no operators' do
          expect(frontend_filterable).not_to be_filterable(['String'])
        end

        it 'returns true with includeAll' do
          expect(frontend_filterable).to be_filterable(['String'], [Operators::INCLUDES_ALL])
        end

        it 'returns false with type Point' do
          expect(frontend_filterable).not_to be_filterable('Point')
          expect(frontend_filterable).not_to be_filterable('Point', Operators.all)
        end

        it 'returns false with type nested types' do
          types = { 'firstName' => 'String', 'lastName' => 'String' }
          expect(frontend_filterable).not_to be_filterable(types)
        end
      end
    end
  end
end
