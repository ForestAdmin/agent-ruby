module ForestAdminDatasourceMambuPayments
  RSpec.describe Query::ConditionTreeTranslator do
    let(:leaf_klass)   { ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf }
    let(:branch_klass) { ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeBranch }

    let(:filters) do
      {
        'connected_account_id' => { ops: %w[equal in] },
        'currency' => { ops: %w[equal], param: 'currency_code' }
      }
    end

    def translate(node)
      described_class.call(node, api_filters: filters)
    end

    describe 'happy paths' do
      it 'returns {} for a nil condition tree' do
        expect(described_class.call(nil, api_filters: filters)).to eq({})
      end

      it 'translates an EQUAL leaf to a scalar query param' do
        leaf = leaf_klass.new('connected_account_id', 'equal', 'acc1')
        expect(translate(leaf)).to eq('connected_account_id' => 'acc1')
      end

      it 'translates an IN leaf to an Array (client joins with commas)' do
        leaf = leaf_klass.new('connected_account_id', 'in', %w[a b])
        expect(translate(leaf)).to eq('connected_account_id' => %w[a b])
      end

      it 'honours the param: override' do
        leaf = leaf_klass.new('currency', 'equal', 'EUR')
        expect(translate(leaf)).to eq('currency_code' => 'EUR')
      end

      it 'merges children of a top-level AND branch' do
        branch = branch_klass.new('And', [
                                    leaf_klass.new('connected_account_id', 'equal', 'acc1'),
                                    leaf_klass.new('currency', 'equal', 'EUR')
                                  ])
        expect(translate(branch)).to eq('connected_account_id' => 'acc1', 'currency_code' => 'EUR')
      end
    end

    describe 'unsupported predicates' do
      it 'raises on a leaf field that is not in api_filters' do
        leaf = leaf_klass.new('status', 'equal', 'pending')
        expect { translate(leaf) }
          .to raise_error(UnsupportedOperatorError, /does not yet translate filters on 'status'/)
      end

      it 'raises on a declared field with an undeclared operator' do
        leaf = leaf_klass.new('currency', 'not_equal', 'EUR')
        expect { translate(leaf) }
          .to raise_error(UnsupportedOperatorError, /not supported on field 'currency'/)
      end

      it 'raises on a top-level OR aggregator' do
        branch = branch_klass.new('Or', [
                                    leaf_klass.new('connected_account_id', 'equal', 'a'),
                                    leaf_klass.new('connected_account_id', 'equal', 'b')
                                  ])
        expect { translate(branch) }
          .to raise_error(UnsupportedOperatorError, /do not support OR aggregation/)
      end

      it 'raises when two children map to the same query param' do
        branch = branch_klass.new('And', [
                                    leaf_klass.new('connected_account_id', 'equal', 'a'),
                                    leaf_klass.new('connected_account_id', 'in', %w[b c])
                                  ])
        expect { translate(branch) }
          .to raise_error(UnsupportedOperatorError, /Conflicting predicates on 'connected_account_id'/)
      end

      it 'raises on EQUAL with a nil value (use PRESENT / BLANK instead)' do
        leaf = leaf_klass.new('connected_account_id', 'equal', nil)
        expect { translate(leaf) }
          .to raise_error(UnsupportedOperatorError, /value on 'connected_account_id' is nil/)
      end

      it 'raises on IN with an empty array (would silently match everything)' do
        leaf = leaf_klass.new('connected_account_id', 'in', [])
        expect { translate(leaf) }
          .to raise_error(UnsupportedOperatorError, /empty array/)
      end

      it 'raises with empty api_filters: any non-id predicate fails loud' do
        leaf = leaf_klass.new('connected_account_id', 'equal', 'a')
        expect { described_class.call(leaf, api_filters: {}) }
          .to raise_error(UnsupportedOperatorError)
      end
    end
  end
end
