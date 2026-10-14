require 'spec_helper'

module ForestAdminDatasourceActiveRecord
  include ForestAdminDatasourceToolkit::Components::Query

  describe Utils::ActiveRecordSerializer do
    subject(:serializer) { described_class.new(Projection.new, {}) }

    describe '#target_model' do
      it 'resolves a belongs_to hop to its target model' do
        expect(serializer.target_model(Account, ['supplier'])).to eq(Supplier)
      end

      it 'resolves a has_one :through chain to the final target model' do
        expect(serializer.target_model(Account, ['order'])).to eq(Order)
      end

      it 'returns nil when a hop is not an association' do
        expect(serializer.target_model(Account, ['not_a_relation'])).to be_nil
      end

      it 'keys its memo by root model as well as relation path' do
        expect(serializer.target_model(Account, ['supplier'])).to eq(Supplier)
        expect(serializer.target_model(Supplier, ['supplier'])).to be_nil
      end
    end

    describe '#serialize' do
      it 'serializes the base attributes when the projection is nil' do
        account = Account.new(supplier: Supplier.new(name: 'ACME'))

        expect(described_class.new(nil).serialize(account)).to eq(account.attributes)
      end
    end

    describe 'per-list footprint' do
      let(:projection) { Projection.new(['id', 'supplier:name', 'account_history:id']) }
      let(:accounts) do
        Array.new(20) { Account.new(supplier: Supplier.new(name: 'ACME'), account_history: AccountHistory.new) }
      end
      let(:expected) do
        accounts.map do |account|
          account.attributes.merge('supplier' => { 'name' => 'ACME' }, 'account_history' => { 'id' => nil })
        end
      end

      it 'resolves the projection tree once, whatever the row count' do
        allow(projection).to receive(:relations).and_call_original
        serializer = described_class.new(projection, {})
        allow(Projection).to receive(:new).and_call_original

        expect(accounts.map { |account| serializer.serialize(account) }).to eq(expected)
        expect(projection).to have_received(:relations).once
        expect(Projection).not_to have_received(:new)
      end

      it 'reflects on belongs_to associations once per model, whatever the row count' do
        allow(Account).to receive(:reflect_on_all_associations).and_call_original
        allow(Supplier).to receive(:reflect_on_all_associations).and_call_original
        serializer = described_class.new(projection, {})

        expect(accounts.map { |account| serializer.serialize(account) }).to eq(expected)
        expect(Account).to have_received(:reflect_on_all_associations).with(:belongs_to).once
        expect(Supplier).to have_received(:reflect_on_all_associations).with(:belongs_to).once
      end

      it 'computes Projection#relations as many times for one row as for many on a JOINed list', :db_truncation do
        create_account = -> { Account.create!(supplier: Supplier.create!(name: 'ACME'), account_history: AccountHistory.create!) }
        query = Utils::Query.new(Collection.new(Datasource.new({ adapter: 'sqlite3', database: 'db/database.db' }), Account),
                                 Projection.new(['id', 'supplier:name', 'account_history:id']), Filter.new)
        query.build
        expect(query.joined_relations.keys).to include('supplier', 'account_history')

        create_account.call
        one_row = count_relations_calls { |list_projection| list_accounts(list_projection) }
        4.times { create_account.call }

        expect(count_relations_calls { |list_projection| list_accounts(list_projection) }).to eq(one_row)
      end

      def list_accounts(list_projection)
        Datasource.new({ adapter: 'sqlite3', database: 'db/database.db' })
                  .get_collection('Account').list(nil, Filter.new, list_projection)
      end

      def count_relations_calls
        count = 0
        spy = lambda do |instance|
          allow(instance).to receive(:relations).and_wrap_original do |original, **options|
            count += 1
            original.call(**options)
          end
          instance
        end
        allow(Projection).to(receive(:new).and_wrap_original { |original, *args| spy.call(original.call(*args)) })

        yield Projection.new(['id', 'supplier:name', 'account_history:id'])
        count
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
        result = described_class.new(Projection.new(['id', 'notable_type']), {}).serialize(note)
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

    describe 'a polymorphic relation nested under another relation', :db_truncation do
      let(:datasource) do
        Datasource.new({ adapter: 'sqlite3', database: 'db/database.db' }, support_polymorphic_relations: true)
      end

      before do
        Address.delete_all
        User.delete_all
        Car.unscoped.delete_all
        Category.delete_all
        car = Car.unscoped.create!(id: 11, reference: 'CAR11', category: Category.create!(label: 'Compact'))
        @user = User.create!(first_name: 'Alice', last_name: 'Smith', car: car)
        Address.create!(addressable: @user, street: '1 rue de la Paix')
      end

      it 'carries the type and foreign key that the linkage of the phantom target is rebuilt from' do
        projection = Projection.new(['id', 'address:addressable:*', 'address:addressable_type',
                                     'address:addressable_id'])

        result = datasource.get_collection('User').list(nil, Filter.new, projection)

        expect(result.first['address']).to include(
          'addressable_type' => 'User', 'addressable_id' => @user.id, 'addressable' => { '*' => nil }
        )
      end

      it 'hydrates a plain field through a polymorphic one-to-one hop' do
        result = datasource.get_collection('User').list(nil, Filter.new, Projection.new(['id', 'address:street']))

        expect(result.first['address']['street']).to eq('1 rue de la Paix')
      end
    end
  end
end
