require 'spec_helper'

module ForestAdminAuditTrail
  module Stores
    describe InMemoryStore do
      subject(:store) { described_class.new }

      def record(over = {})
        AuditRecord.new(
          operation: 'update', collection: 'accounts', record_id: '1',
          previous_values: {}, new_values: {}, timestamp: '2026-01-02T03:04:05.000Z', **over
        )
      end

      it 'returns rows for the queried record, oldest first' do
        store.append(record(timestamp: '2026-01-02T03:04:06.000Z', correlation_key: 'b'))
        store.append(record(timestamp: '2026-01-02T03:04:05.000Z', correlation_key: 'a'))
        store.append(record(record_id: '2', correlation_key: 'other'))

        history = store.list_by_record(collection: 'accounts', record_id: '1')

        expect(history.map(&:correlation_key)).to eq(%w[a b])
      end

      it 'honors skip and limit' do
        3.times { |i| store.append(record(timestamp: "2026-01-02T03:04:0#{i}.000Z", correlation_key: i.to_s)) }

        page = store.list_by_record(collection: 'accounts', record_id: '1', skip: 1, limit: 1)

        expect(page.map(&:correlation_key)).to eq(['1'])
      end

      it 'returns an empty array when nothing matches' do
        store.append(record)

        expect(store.list_by_record(collection: 'accounts', record_id: 'missing')).to eq([])
      end

      it 'sorts newest first when order is desc, ties keeping append order' do
        store.append(record(timestamp: '2026-01-02T03:04:05.000Z', correlation_key: 'a'))
        store.append(record(timestamp: '2026-01-02T03:04:06.000Z', correlation_key: 'b'))
        store.append(record(timestamp: '2026-01-02T03:04:05.000Z', correlation_key: 'a2'))

        history = store.list_by_record(collection: 'accounts', record_id: '1', order: 'desc')

        expect(history.map(&:correlation_key)).to eq(%w[b a a2])
      end

      it 'filters by user_ids, dropping non-matching actors' do
        store.append(record(user_id: 7, correlation_key: 'keep'))
        store.append(record(user_id: 9, correlation_key: 'drop'))

        history = store.list_by_record(collection: 'accounts', record_id: '1', user_ids: [7])

        expect(history.map(&:correlation_key)).to eq(['keep'])
      end

      it 'filters by inclusive start/end timestamps regardless of string format' do
        store.append(record(timestamp: '2026-01-02T03:04:05.000Z', correlation_key: 'before'))
        store.append(record(timestamp: '2026-01-02T03:04:07.000Z', correlation_key: 'inside'))
        store.append(record(timestamp: '2026-01-02T03:04:09.000Z', correlation_key: 'after'))

        history = store.list_by_record(
          collection: 'accounts', record_id: '1',
          start_timestamp: '2026-01-02T03:04:06.000Z', end_timestamp: '2026-01-02T03:04:08.000Z'
        )

        expect(history.map(&:correlation_key)).to eq(['inside'])
      end

      it 'counts matches independently of skip/limit' do
        store.append(record(user_id: 7))
        store.append(record(user_id: 7))
        store.append(record(user_id: 9))

        expect(store.count_by_record(collection: 'accounts', record_id: '1')).to eq(3)
        expect(store.count_by_record(collection: 'accounts', record_id: '1', user_ids: [7])).to eq(2)
      end
    end
  end
end
