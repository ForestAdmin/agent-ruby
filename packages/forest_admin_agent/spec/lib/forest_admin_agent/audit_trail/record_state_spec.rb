require 'spec_helper'

module ForestAdminAgent
  module AuditTrail
    describe RecordState do
      def entry(operation, previous_values = {}, new_values = {})
        AuditRecord.new(operation: operation, collection: 'orders', record_id: '1',
                        previous_values: previous_values, new_values: new_values)
      end

      it 'gives the record back untouched when nothing happened after the instant' do
        current = { 'id' => 1, 'status' => 'shipped' }

        expect(described_class.at(current, [])).to eq(current)
      end

      it 'undoes updates from newest to oldest' do
        current = { 'id' => 1, 'status' => 'shipped' }
        entries = [
          entry('update', { 'status' => 'paid' }, { 'status' => 'shipped' }),
          entry('update', { 'status' => 'draft' }, { 'status' => 'paid' })
        ]

        expect(described_class.at(current, entries)).to eq({ 'id' => 1, 'status' => 'draft' })
      end

      it 'leaves columns the entries never touched alone' do
        current = { 'id' => 1, 'status' => 'shipped', 'note' => 'keep me' }
        entries = [entry('update', { 'status' => 'paid' }, { 'status' => 'shipped' })]

        expect(described_class.at(current, entries)['note']).to eq('keep me')
      end

      it 'reports no record at all when it was created after the instant' do
        current = { 'id' => 1, 'status' => 'draft' }
        entries = [entry('create', {}, { 'status' => 'draft' })]

        expect(described_class.at(current, entries)).to be_nil
      end

      # The record is gone now, so the walk starts from nothing and the delete brings the whole row back.
      it 'restores a deleted record from the snapshot the delete recorded' do
        entries = [entry('delete', { 'status' => 'shipped', 'note' => 'bye' }, {})]

        expect(described_class.at(nil, entries)).to eq({ 'status' => 'shipped', 'note' => 'bye' })
      end

      it 'keeps undoing older entries after restoring a delete' do
        entries = [
          entry('delete', { 'status' => 'shipped' }, {}),
          entry('update', { 'status' => 'paid' }, { 'status' => 'shipped' })
        ]

        expect(described_class.at(nil, entries)).to eq({ 'status' => 'paid' })
      end

      # A create can sit on top of an older life of the same id: nil for the create, then the older
      # delete brings that life back.
      it 'walks past a re-created id into its previous life' do
        entries = [
          entry('create', {}, { 'status' => 'draft' }),
          entry('delete', { 'status' => 'archived' }, {})
        ]

        expect(described_class.at({ 'status' => 'draft' }, entries)).to eq({ 'status' => 'archived' })
      end

      # An action row's two value columns hold the submitted form and the action's answer, not a record's
      # before and after: applying either would corrupt the rebuild.
      it 'ignores smart-action rows, whichever way they went' do
        current = { 'status' => 'shipped' }
        entries = [
          entry('action', { 'status' => 'submitted value' }, { 'type' => 'Success' }),
          entry('action_failed', { 'status' => 'submitted value' }, {})
        ]

        expect(described_class.at(current, entries)).to eq(current)
      end

      it 'undoes a nested change without disturbing the rest of the object' do
        current = { 'address' => { 'city' => 'Lyon', 'zip' => '69001' } }
        entries = [entry('update', { 'address' => { 'city' => 'Paris' } }, { 'address' => { 'city' => 'Lyon' } })]

        expect(described_class.at(current, entries)).to eq(
          { 'address' => { 'city' => 'Paris', 'zip' => '69001' } }
        )
      end

      # The whole point of the absent-vs-nil encoding: a key the change added has to disappear again,
      # rather than come back holding nil.
      it 'removes a nested key that the change had introduced' do
        current = { 'address' => { 'city' => 'Lyon', 'zip' => '69001' } }
        entries = [entry('update', { 'address' => {} }, { 'address' => { 'zip' => '69001' } })]

        expect(described_class.at(current, entries)).to eq({ 'address' => { 'city' => 'Lyon' } })
      end

      it 'puts back a nested key holding nil that the change had removed' do
        current = { 'address' => { 'city' => 'Lyon' } }
        entries = [entry('update', { 'address' => { 'zip' => nil } }, { 'address' => {} })]

        expect(described_class.at(current, entries)).to eq({ 'address' => { 'city' => 'Lyon', 'zip' => nil } })
      end
    end
  end
end
