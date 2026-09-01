module ForestAdminDatasourceIntercom
  RSpec.describe Query::ConditionTreeTranslator do
    let(:operators) { ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators }
    let(:nodes) { ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes }
    let(:endpoint) { Query::SearchFields.fetch('conversations') }

    def translate(tree, timezone: 'UTC')
      described_class.call(tree, endpoint: endpoint, collection: 'IntercomConversation', timezone: timezone)
    end

    def leaf(field, operator, value = nil)
      nodes::ConditionTreeLeaf.new(field, operator, value)
    end

    def branch(aggregator, *conditions)
      nodes::ConditionTreeBranch.new(aggregator, conditions)
    end

    describe 'a leaf' do
      it 'writes the Intercom field, operator and value the endpoint takes' do
        expect(translate(leaf('state', operators::EQUAL, 'open')))
          .to eq({ 'field' => 'state', 'operator' => '=', 'value' => 'open' })
      end

      # The column is the operator's name for it; the field is Intercom's. They
      # are not the same on a statistic, which the column flattens onto the row.
      it 'filters a flattened statistic through the field Intercom nests it in' do
        expect(translate(leaf('closed_at', operators::LESS_THAN, '2026-09-01T00:00:00Z'))['field'])
          .to eq('statistics.last_close_at')
      end

      it 'answers nil for no condition at all, which is a list view' do
        expect(translate(nil)).to be_nil
      end
    end

    describe 'a branch' do
      it 'groups its conditions under the aggregator Intercom spells in capitals' do
        tree = branch('Or', leaf('state', operators::EQUAL, 'open'), leaf('state', operators::EQUAL, 'snoozed'))

        expect(translate(tree)).to eq({ 'operator' => 'OR',
                                        'value' => [{ 'field' => 'state', 'operator' => '=', 'value' => 'open' },
                                                    { 'field' => 'state', 'operator' => '=', 'value' => 'snoozed' }] })
      end

      # The agent builds a tree one branch at a time -- a scope, then a segment,
      # then the operator's filter -- and Intercom allows two levels of nesting.
      # A wrapper around a single condition is a level worth not spending.
      it 'unwraps a branch carrying one condition rather than spending a level on it' do
        tree = branch('And', branch('And', leaf('open', operators::EQUAL, true)))

        expect(translate(tree)).to eq({ 'field' => 'open', 'operator' => '=', 'value' => true })
      end

      it 'nests a group inside a group' do
        tree = branch('And', leaf('open', operators::EQUAL, true),
                      branch('Or', leaf('state', operators::EQUAL, 'open'),
                             leaf('state', operators::EQUAL, 'snoozed')))

        expect(translate(tree)['value'].last['operator']).to eq('OR')
      end

      it 'refuses an aggregator that is neither and nor or' do
        expect { translate(branch('Xor', leaf('open', operators::EQUAL, true))) }
          .to raise_error(UnsupportedOperatorError, /cannot read "Xor" as a condition tree aggregator/)
      end

      # A branch with nothing in it names no record and no filter, so sending it
      # would answer a filtered question with the whole collection.
      it 'refuses a branch carrying no condition' do
        expect { translate(branch('And')) }
          .to raise_error(UnsupportedOperatorError, /carrying no condition/)
      end

      it 'refuses a node that is neither a leaf nor a branch' do
        expect { translate(Object.new) }
          .to raise_error(UnsupportedOperatorError, /cannot read Object as a condition/)
      end
    end

    describe 'what it will not translate' do
      # The whole point of the lot: a condition dropped on the way to Intercom
      # comes back as an unfiltered page that looks filtered.
      it 'refuses a column the endpoint does not filter, and names what it does' do
        expect { translate(leaf('contact_name', operators::EQUAL, 'Camille')) }
          .to raise_error(UnsupportedOperatorError, /cannot filter "contact_name".*Contacts endpoint/m)
      end

      it 'refuses a column nothing declares, listing the ones it takes' do
        expect { translate(leaf('nope', operators::EQUAL, 'x')) }
          .to raise_error(UnsupportedOperatorError, /takes no filter on it. Filter on one of: state, open/)
      end

      # None of these collections declares a relation yet, so a `relation:field`
      # can only come from a scope or a segment written against another schema.
      it 'refuses a condition on a relation by name' do
        expect { translate(leaf('contact:email', operators::EQUAL, 'camille@acme.test')) }
          .to raise_error(UnsupportedOperatorError, /declares no relation/)
      end

      it 'refuses an operator the endpoint does not answer on that field' do
        expect { translate(leaf('state', operators::CONTAINS, 'op')) }
          .to raise_error(UnsupportedOperatorError, /answers equal, not_equal on "state" and nothing else/)
      end

      # Published on a date column by the toolkit and refused by this endpoint:
      # the datasource cannot express an equality on a day it truncates.
      it 'refuses an equality on a date, which is not one of the two bounds' do
        expect { translate(leaf('created_at', operators::EQUAL, '2026-09-01T00:00:00Z')) }
          .to raise_error(UnsupportedOperatorError, /answers greater_than, less_than/)
      end
    end
  end
end
