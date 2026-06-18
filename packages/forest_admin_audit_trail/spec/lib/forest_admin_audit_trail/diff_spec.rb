require 'spec_helper'

module ForestAdminAuditTrail
  describe Diff do
    describe '.diff' do
      it 'returns nil when values are deeply equal regardless of hash key order' do
        expect(described_class.diff({ 'a' => 1, 'b' => 2 }, { 'b' => 2, 'a' => 1 })).to be_nil
      end

      it 'keeps only the changed leaf of a nested object' do
        before = { 'city' => 'Paris', 'zip' => '75001' }
        after = { 'city' => 'Lyon', 'zip' => '75001' }

        expect(described_class.diff(before, after)).to eq(
          previous: { 'city' => 'Paris' },
          next: { 'city' => 'Lyon' }
        )
      end

      it 'diffs an array of objects index by index' do
        before = [{ 'name' => 'a' }, { 'name' => 'b' }]
        after = [{ 'name' => 'a' }, { 'name' => 'c' }]

        expect(described_class.diff(before, after)).to eq(
          previous: { 1 => { 'name' => 'b' } },
          next: { 1 => { 'name' => 'c' } }
        )
      end

      it 'keeps scalars and primitive arrays whole' do
        expect(described_class.diff(%w[a b], %w[a c])).to eq(previous: %w[a b], next: %w[a c])
      end

      it 'reports nil for a newly set or cleared value' do
        expect(described_class.diff(nil, 'x')).to eq(previous: nil, next: 'x')
        expect(described_class.diff('x', nil)).to eq(previous: 'x', next: nil)
      end
    end

    describe '.changed_values' do
      it 'only records writable columns present in the patch that actually changed' do
        before = { 'status' => 'open', 'name' => 'Acme', 'ignored' => 1 }
        patch = { 'status' => 'closed', 'name' => 'Acme' }

        expect(described_class.changed_values(before, patch, %w[status name])).to eq(
          previous_values: { 'status' => 'open' },
          new_values: { 'status' => 'closed' }
        )
      end
    end
  end
end
