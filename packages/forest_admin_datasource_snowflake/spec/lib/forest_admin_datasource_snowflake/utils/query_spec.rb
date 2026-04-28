require 'spec_helper'

RSpec.describe ForestAdminDatasourceSnowflake::Utils::Query do
  let(:collection) { instance_double('Collection', table_name: 'BILLING_USAGE') }

  describe '#to_sql' do
    it 'selects projected columns from the table when no filter is given' do
      sql, binds = described_class.new(
        collection,
        projection: Projection.new(%w[id customer_id amount_cents])
      ).to_sql

      expect(sql).to eq('SELECT "id", "customer_id", "amount_cents" FROM "BILLING_USAGE"')
      expect(binds).to eq([])
    end

    it 'selects * when projection is missing' do
      sql, = described_class.new(collection).to_sql
      expect(sql).to eq('SELECT * FROM "BILLING_USAGE"')
    end

    it 'translates a single equal leaf to a parameterized WHERE with quoted column' do
      filter = Filter.new(
        condition_tree: ConditionTreeLeaf.new('CUSTOMER_ID', Operators::EQUAL, 42)
      )
      sql, binds = described_class.new(collection, projection: Projection.new(['id']), filter: filter).to_sql

      expect(sql).to eq('SELECT "id" FROM "BILLING_USAGE" WHERE "CUSTOMER_ID" = ?')
      expect(binds).to eq([42])
    end

    it 'composes branches with AND/OR and bind values in declaration order' do
      gt_amount = ConditionTreeLeaf.new('AMOUNT', Operators::GREATER_THAN, 1000)
      in_customer = ConditionTreeLeaf.new('CUSTOMER', Operators::IN, [1, 2, 3])
      or_branch = ConditionTreeBranch.new('Or', [gt_amount, in_customer])
      eq_status = ConditionTreeLeaf.new('STATUS', Operators::EQUAL, 'paid')
      filter = Filter.new(condition_tree: ConditionTreeBranch.new('And', [eq_status, or_branch]))
      sql, binds = described_class.new(collection, projection: Projection.new(['id']), filter: filter).to_sql

      expect(sql).to eq(
        'SELECT "id" FROM "BILLING_USAGE" WHERE ("STATUS" = ? AND ("AMOUNT" > ? OR "CUSTOMER" IN (?, ?, ?)))'
      )
      expect(binds).to eq(['paid', 1000, 1, 2, 3])
    end

    it 'translates IN with empty list to an always-false predicate' do
      filter = Filter.new(condition_tree: ConditionTreeLeaf.new('id', Operators::IN, []))
      sql, binds = described_class.new(collection, projection: Projection.new(['id']), filter: filter).to_sql

      expect(sql).to eq('SELECT "id" FROM "BILLING_USAGE" WHERE 1=0')
      expect(binds).to eq([])
    end

    it 'translates I_CONTAINS into a case-insensitive LIKE with wildcards' do
      filter = Filter.new(condition_tree: ConditionTreeLeaf.new('EVENT_TYPE', Operators::I_CONTAINS, 'login'))
      sql, binds = described_class.new(collection, projection: Projection.new(['id']), filter: filter).to_sql

      expect(sql).to include('LOWER("EVENT_TYPE") LIKE LOWER(?)')
      expect(binds).to eq(['%login%'])
    end

    it 'translates STARTS_WITH and ENDS_WITH with the right wildcards' do
      sw = Filter.new(condition_tree: ConditionTreeLeaf.new('NAME', Operators::STARTS_WITH, 'foo'))
      ew = Filter.new(condition_tree: ConditionTreeLeaf.new('NAME', Operators::ENDS_WITH,   'bar'))

      sw_sql, sw_binds = described_class.new(collection, projection: Projection.new(['id']), filter: sw).to_sql
      ew_sql, ew_binds = described_class.new(collection, projection: Projection.new(['id']), filter: ew).to_sql

      expect(sw_sql).to include('"NAME" LIKE ?')
      expect(ew_sql).to include('"NAME" LIKE ?')
      expect(sw_binds).to eq(['foo%'])
      expect(ew_binds).to eq(['%bar'])
    end

    it 'translates PRESENT / MISSING / BLANK without bind values' do
      [Operators::PRESENT, Operators::MISSING, Operators::BLANK].each do |op|
        filter = Filter.new(condition_tree: ConditionTreeLeaf.new('id', op, nil))
        _, binds = described_class.new(collection, projection: Projection.new(['id']), filter: filter).to_sql
        expect(binds).to eq([]), "expected no binds for #{op}"
      end
    end

    it 'appends ORDER BY for sort directives, with quoted columns' do
      filter = Filter.new(sort: [{ field: 'OCCURRED_AT', ascending: false }, { field: 'id', ascending: true }])
      sql, = described_class.new(collection, projection: Projection.new(['id']), filter: filter).to_sql

      expect(sql).to end_with('ORDER BY "OCCURRED_AT" DESC, "id" ASC')
    end

    it 'appends LIMIT and OFFSET when filter has a Page' do
      filter = Filter.new(page: Page.new(offset: 30, limit: 15))
      sql, = described_class.new(collection, projection: Projection.new(['id']), filter: filter).to_sql

      expect(sql).to end_with('LIMIT 15 OFFSET 30')
    end

    it 'rejects operators that the toolkit allows but our translator does not yet implement' do
      filter = Filter.new(condition_tree: ConditionTreeLeaf.new('id', Operators::MATCH, /foo/))
      expect do
        described_class.new(collection, projection: Projection.new(['id']), filter: filter).to_sql
      end.to raise_error(ForestAdminDatasourceSnowflake::Error, /Unsupported operator/)
    end

    it 'quotes identifiers containing reserved words or special chars correctly' do
      filter = Filter.new(condition_tree: ConditionTreeLeaf.new('order', Operators::EQUAL, 1))
      sql, = described_class.new(collection, projection: Projection.new(['select']), filter: filter).to_sql

      expect(sql).to include('"order" = ?')
      expect(sql).to include('"select"')
    end
  end

  describe '#to_aggregate_sql' do
    it 'builds COUNT(*) with no group_by' do
      sql, binds, groups = described_class.new(
        collection,
        aggregation: Aggregation.new(operation: 'Count')
      ).to_aggregate_sql

      expect(sql).to eq('SELECT COUNT(*) FROM "BILLING_USAGE"')
      expect(binds).to eq([])
      expect(groups).to eq([])
    end

    it 'builds SUM with WHERE and GROUP BY, returns group columns alongside SQL' do
      filter = Filter.new(condition_tree: ConditionTreeLeaf.new('STATUS', Operators::EQUAL, 'paid'))
      sql, binds, groups = described_class.new(
        collection,
        filter: filter,
        aggregation: Aggregation.new(
          operation: 'Sum', field: 'AMOUNT_CENTS',
          groups: [{ field: 'CUSTOMER_ID' }]
        )
      ).to_aggregate_sql

      expect(sql).to eq(
        'SELECT SUM("AMOUNT_CENTS"), "CUSTOMER_ID" FROM "BILLING_USAGE" WHERE "STATUS" = ? GROUP BY "CUSTOMER_ID"'
      )
      expect(binds).to eq(['paid'])
      expect(groups).to eq(['CUSTOMER_ID'])
    end

    it 'caps results when limit is provided' do
      sql, = described_class.new(
        collection,
        aggregation: Aggregation.new(operation: 'Count', groups: [{ field: 'STATUS' }]),
        limit: 5
      ).to_aggregate_sql

      expect(sql).to end_with('LIMIT 5')
    end

    it 'rejects aggregation operations the toolkit allows but our translator does not implement' do
      agg = instance_double('Aggregation', operation: 'Variance', field: 'x', groups: [])
      expect do
        described_class.new(collection, aggregation: agg).to_aggregate_sql
      end.to raise_error(ForestAdminDatasourceSnowflake::Error, /Unsupported aggregation/)
    end
  end
end
