require 'spec_helper'

module ForestAdminAgent
  module AuditTrail
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

        # A key holding nil and a missing key have to stay tellable apart, so the side where the key does
        # not exist simply does not carry it. Nothing sentinel-shaped reaches the database.
        it 'reports a key that disappeared by leaving it out of the new values' do
          expect(described_class.diff({ 'flag' => nil }, {})).to eq(
            previous: { 'flag' => nil },
            next: {}
          )
        end

        it 'reports a key that appeared by leaving it out of the previous values' do
          expect(described_class.diff({}, { 'flag' => nil })).to eq(
            previous: {},
            next: { 'flag' => nil }
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

      describe '.revert' do
        it 'restores a scalar' do
          expect(described_class.revert('Lyon', 'Paris', 'Lyon')).to eq('Paris')
        end

        it 'restores only the touched keys, leaving the rest of the object alone' do
          current = { 'city' => 'Lyon', 'zip' => '69001', 'country' => 'FR' }

          expect(described_class.revert(current, { 'city' => 'Paris' }, { 'city' => 'Lyon' })).to eq(
            { 'city' => 'Paris', 'zip' => '69001', 'country' => 'FR' }
          )
        end

        it 'removes a key the change had added' do
          expect(described_class.revert({ 'city' => 'Lyon', 'zip' => '69001' }, {}, { 'zip' => '69001' })).to eq(
            { 'city' => 'Lyon' }
          )
        end

        it 'puts back a key the change had removed, nil value included' do
          expect(described_class.revert({ 'city' => 'Lyon' }, { 'zip' => nil }, {})).to eq(
            { 'city' => 'Lyon', 'zip' => nil }
          )
        end

        it 'walks nested objects' do
          current = { 'address' => { 'city' => 'Lyon', 'zip' => '69001' }, 'name' => 'Acme' }
          previous = { 'address' => { 'city' => 'Paris' } }
          changed = { 'address' => { 'city' => 'Lyon' } }

          expect(described_class.revert(current, previous, changed)).to eq(
            { 'address' => { 'city' => 'Paris', 'zip' => '69001' }, 'name' => 'Acme' }
          )
        end

        it 'restores an element of an array of objects, JSON string indexes included' do
          current = [{ 'name' => 'a' }, { 'name' => 'c' }]

          expect(described_class.revert(current, { '1' => { 'name' => 'b' } }, { '1' => { 'name' => 'c' } })).to eq(
            [{ 'name' => 'a' }, { 'name' => 'b' }]
          )
        end

        it 'drops an element the change had appended' do
          current = [{ 'name' => 'a' }, { 'name' => 'b' }]

          expect(described_class.revert(current, {}, { '1' => { 'name' => 'b' } })).to eq([{ 'name' => 'a' }])
        end

        it 'replaces the value as a whole when the change was not structural' do
          expect(described_class.revert({ 'city' => 'Lyon' }, nil, { 'city' => 'Lyon' })).to be_nil
        end

        # A round trip is the property that matters: diff then revert gives the original back.
        it 'undoes any diff it is given' do
          [
            [{ 'a' => 1, 'b' => { 'c' => 2, 'd' => nil } }, { 'a' => 1, 'b' => { 'c' => 3 } }],
            [{ 'a' => nil }, { 'a' => 'set' }],
            [{ 'list' => [{ 'x' => 1 }, { 'x' => 2 }] }, { 'list' => [{ 'x' => 1 }, { 'x' => 9 }] }],
            ['plain', 'changed']
          ].each do |before, after|
            delta = described_class.diff(before, after)

            expect(described_class.revert(after, delta[:previous], delta[:next])).to eq(before)
          end
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
end
