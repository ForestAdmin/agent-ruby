require 'date'

RSpec.describe ForestAdminDatasourceZendesk::Query::ConditionTreeTranslator do
  Leaf   = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf
  Branch = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeBranch

  def translate(node)
    described_class.call(node)
  end

  it 'returns empty string when condition tree is nil' do
    expect(translate(nil)).to eq('')
  end

  describe 'leaf operators' do
    it 'translates EQUAL' do
      expect(translate(Leaf.new('status', 'equal', 'open'))).to eq('status:open')
    end

    it 'translates NOT_EQUAL' do
      expect(translate(Leaf.new('status', 'not_equal', 'open'))).to eq('-status:open')
    end

    it 'translates IN as multiple equality clauses' do
      expect(translate(Leaf.new('status', 'in', %w[open pending])))
        .to eq('status:open status:pending')
    end

    it 'translates NOT_IN as multiple negated clauses' do
      expect(translate(Leaf.new('status', 'not_in', %w[closed solved])))
        .to eq('-status:closed -status:solved')
    end

    it 'translates GREATER_THAN' do
      expect(translate(Leaf.new('priority', 'greater_than', 2))).to eq('priority>2')
    end

    it 'translates LESS_THAN' do
      expect(translate(Leaf.new('priority', 'less_than', 5))).to eq('priority<5')
    end

    it 'translates AFTER on a Date as start-of-day in UTC by default' do
      result = translate(Leaf.new('created_at', 'after', Date.new(2026, 1, 15)))
      expect(result).to eq('created_at>2026-01-15T00:00:00Z')
    end

    it 'translates BEFORE on a Date as start-of-day in UTC by default' do
      result = translate(Leaf.new('updated_at', 'before', Date.new(2026, 4, 1)))
      expect(result).to eq('updated_at<2026-04-01T00:00:00Z')
    end

    it 'translates PRESENT as field:*' do
      expect(translate(Leaf.new('assignee_id', 'present'))).to eq('assignee_id:*')
    end

    it 'translates BLANK as -field:*' do
      expect(translate(Leaf.new('assignee_id', 'blank'))).to eq('-assignee_id:*')
    end

    it 'raises on unsupported operator (e.g. CONTAINS)' do
      expect { translate(Leaf.new('subject', 'contains', 'foo')) }
        .to raise_error(ForestAdminDatasourceZendesk::UnsupportedOperatorError, /contains/)
    end
  end

  describe 'requester_email special case' do
    it 'rewrites requester_email = X to requester:X' do
      expect(translate(Leaf.new('requester_email', 'equal', 'a@b.com')))
        .to eq('requester:a@b.com')
    end

    it 'falls through to generic field:value for non-equal operators on requester_email' do
      # Generic EQUAL would give requester_email:VALUE; only EQUAL gets the rewrite.
      expect(translate(Leaf.new('requester_email', 'present')))
        .to eq('requester_email:*')
    end
  end

  describe 'value formatting' do
    it 'quotes string values containing spaces' do
      expect(translate(Leaf.new('subject', 'equal', 'two words')))
        .to eq('subject:"two words"')
    end

    it 'serialises Time as ISO8601 UTC' do
      t = Time.utc(2026, 4, 27, 9, 30, 0)
      expect(translate(Leaf.new('updated_at', 'after', t)))
        .to eq('updated_at>2026-04-27T09:30:00Z')
    end

    it 'raises rather than emit a malformed `field:` clause for nil values' do
      expect { translate(Leaf.new('subject', 'equal', nil)) }
        .to raise_error(ForestAdminDatasourceZendesk::UnsupportedOperatorError, /PRESENT or BLANK/)
    end
  end

  describe 'timezone handling' do
    it 'interprets a Date as start-of-day in the supplied timezone, converted to UTC' do
      # Jan 15 is outside of DST in Paris (UTC+1), so 00:00 local is 23:00 UTC the previous day.
      result = described_class.call(Leaf.new('created_at', 'after', Date.new(2026, 1, 15)),
                                    timezone: 'Europe/Paris')
      expect(result).to eq('created_at>2026-01-14T23:00:00Z')
    end

    it 'respects DST shifts (Apr 27 in Paris is UTC+2)' do
      result = described_class.call(Leaf.new('created_at', 'after', Date.new(2026, 4, 27)),
                                    timezone: 'Europe/Paris')
      expect(result).to eq('created_at>2026-04-26T22:00:00Z')
    end

    it 'falls back to UTC when the timezone is unknown' do
      result = described_class.call(Leaf.new('created_at', 'after', Date.new(2026, 4, 27)),
                                    timezone: 'Mars/Olympus_Mons')
      expect(result).to eq('created_at>2026-04-27T00:00:00Z')
    end

    it 'still emits Time values as UTC ISO8601 regardless of timezone arg' do
      t = Time.utc(2026, 4, 27, 9, 30, 0)
      result = described_class.call(Leaf.new('updated_at', 'after', t), timezone: 'Europe/Paris')
      expect(result).to eq('updated_at>2026-04-27T09:30:00Z')
    end
  end

  describe 'custom field mapping' do
    around do |ex|
      previous = described_class.custom_field_mapping
      described_class.custom_field_mapping = { 'custom_360001' => 'custom_field_360001' }
      ex.run
      described_class.custom_field_mapping = previous
    end

    it 'rewrites a custom field column name to the Zendesk Search field' do
      expect(translate(Leaf.new('custom_360001', 'equal', 'gold')))
        .to eq('custom_field_360001:gold')
    end

    it 'leaves non-mapped fields untouched' do
      expect(translate(Leaf.new('status', 'equal', 'open'))).to eq('status:open')
    end
  end

  describe 'branches (aggregators)' do
    it 'joins AND children with spaces' do
      branch = Branch.new('And', [
                            Leaf.new('status', 'equal', 'open'),
                            Leaf.new('priority', 'equal', 'high')
                          ])
      expect(translate(branch)).to eq('status:open priority:high')
    end

    it 'raises on OR aggregator' do
      branch = Branch.new('Or', [
                            Leaf.new('status', 'equal', 'open'),
                            Leaf.new('status', 'equal', 'pending')
                          ])
      expect { translate(branch) }
        .to raise_error(ForestAdminDatasourceZendesk::UnsupportedOperatorError, /OR/i)
    end

    it 'recurses into nested AND branches' do
      inner  = Branch.new('And', [Leaf.new('status', 'equal', 'open')])
      outer  = Branch.new('And', [inner, Leaf.new('priority', 'equal', 'urgent')])
      expect(translate(outer)).to eq('status:open priority:urgent')
    end
  end
end
