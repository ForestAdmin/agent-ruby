module ForestAdminDatasourceMambuPayments
  module PivotResolutionSupport
    Operators = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators
    Leaf = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

    # Slices its records according to the filter's page, so the spec can prove
    # PivotResolution.collect pages past one API window.
    class PagingCollection
      def initialize(records)
        @records = records
      end

      def list(filter, _projection)
        page = filter.page
        @records.slice(page.offset, page.limit) || []
      end
    end

    class FakeContext
      def initialize(records)
        @paging = PagingCollection.new(records)
      end

      def datasource = self

      def get_collection(_name) = @paging
    end
  end

  module Plugins
    module Relations
      RSpec.describe PivotResolution do
        describe '.collect' do
          it 'pages through every matching row, not just the first API page' do
            records = Array.new(250) { |i| { 'transaction_id' => "tx#{i}" } }
            context = PivotResolutionSupport::FakeContext.new(records)
            leaf = PivotResolutionSupport::Leaf.new('payment_id', PivotResolutionSupport::Operators::IN, %w[p1])

            ids = described_class.collect(context, 'MambuReconciliation', leaf, 'transaction_id')

            expect(ids.size).to eq(250)
            expect(ids).to include('tx0', 'tx249')
          end

          it 'flattens array columns and drops blank / duplicate values' do
            records = [
              { 'connected_account_ids' => %w[a b] },
              { 'connected_account_ids' => ['b', '', nil] },
              { 'connected_account_ids' => ['c'] }
            ]
            context = PivotResolutionSupport::FakeContext.new(records)
            leaf = PivotResolutionSupport::Leaf.new('id', PivotResolutionSupport::Operators::IN, %w[x])

            ids = described_class.collect(context, 'MambuInternalAccount', leaf, 'connected_account_ids')

            expect(ids).to contain_exactly('a', 'b', 'c')
          end
        end

        describe '.normalize' do
          it 'wraps an EQUAL scalar and drops blanks for IN' do
            expect(described_class.normalize('a', PivotResolutionSupport::Operators::EQUAL)).to eq(['a'])
            expect(described_class.normalize(['a', '', nil, 'a'], PivotResolutionSupport::Operators::IN)).to eq(['a'])
          end
        end

        describe '.no_match' do
          it 'builds a leaf that matches nothing without tripping the empty-IN guard' do
            leaf = described_class.no_match('connected_account_id')
            expect(leaf.operator).to eq(PivotResolutionSupport::Operators::EQUAL)
            expect(leaf.value).to eq(described_class::NO_MATCH_SENTINEL)
          end
        end
      end
    end
  end
end
