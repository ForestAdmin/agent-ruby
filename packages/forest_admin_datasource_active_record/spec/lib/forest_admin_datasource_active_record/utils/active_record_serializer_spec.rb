require 'spec_helper'

module ForestAdminDatasourceActiveRecord
  include ForestAdminDatasourceToolkit::Components::Query

  describe Utils::ActiveRecordSerializer do
    subject(:serializer) { described_class.new(Account.new, {}) }

    describe '#target_model' do
      it 'resolves a belongs_to hop to its target model' do
        expect(serializer.target_model(['supplier'])).to eq(Supplier)
      end

      it 'resolves a has_one :through chain to the final target model' do
        expect(serializer.target_model(['order'])).to eq(Order)
      end

      it 'returns nil when a hop is not an association' do
        expect(serializer.target_model(['not_a_relation'])).to be_nil
      end
    end

    # Api::Topic is namespaced but stored demodulized as "Topic" (store_full_class_name = false on
    # Api::Note), so polymorphic_class_for("Topic").name == "Api::Topic" -> a real transform.
    # Without normalization these assertions would read the raw "Topic".
    describe 'polymorphic type normalization', :db_truncation do
      let(:datasource) { Datasource.new({ adapter: 'sqlite3', database: 'db/database.db' }) }
      let(:note) do
        n = Api::Note.create!
        n.update_columns(notable_type: 'Topic', notable_id: Api::Topic.create!.id) # legacy demodulized value
        n.reload
      end

      before do
        Account.delete_all
        Api::Note.delete_all
        Api::Topic.delete_all
      end

      it 'qualifies the stored type on the preloaded (hash_object) path' do
        result = described_class.new(note, {}).to_hash(Projection.new(['id', 'notable_type']))
        expect(result['notable_type']).to eq('Api::Topic')
      end

      it 'qualifies the stored type on the JOINed (hash_joined_relation) path' do
        account = Account.create!(supplier: Supplier.create!(name: 'ACME'),
                                  account_history: AccountHistory.create!, note: note)

        query = Utils::Query.new(Collection.new(datasource, Account), Projection.new(['id', 'note:notable_type']),
                                 Filter.new)
        query.build
        expect(query.joined_relations).to have_key('note') # proves the JOINed path, not preload

        result = Collection.new(datasource, Account).list(nil, Filter.new, Projection.new(['id', 'note:notable_type']))
        expect(result.find { |r| r['id'] == account.id }['note']['notable_type']).to eq('Api::Topic')
      end
    end
  end
end
