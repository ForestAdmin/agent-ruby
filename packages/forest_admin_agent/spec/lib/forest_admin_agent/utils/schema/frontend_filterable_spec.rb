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
      end
    end
  end
end
