require 'spec_helper'

module ForestAdminAgent
  module Services
    include ForestAdminDatasourceToolkit
    include ForestAdminDatasourceToolkit::Schema
    include ForestAdminDatasourceToolkit::Components::Query
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

    describe Permissions do
      include_context 'with caller'

      let(:datasource) { build_datasource_with_collections(collections) }
      let(:cards) { datasource.get_collection('cards') }

      let(:collections) do
        [
          build_collection(
            name: 'cards',
            schema: {
              fields: {
                'id' => build_numeric_primary_key,
                'account_id' => build_column(column_type: 'Number'),
                'holder_id' => build_column(column_type: 'Number'),
                'account' => build_many_to_one(foreign_collection: 'accounts', foreign_key: 'account_id'),
                'holder' => build_many_to_one(foreign_collection: 'holders', foreign_key: 'holder_id')
              }
            }
          ),
          build_collection(
            name: 'accounts',
            schema: {
              fields: {
                'id' => build_numeric_primary_key,
                'iban' => build_column(column_type: 'String'),
                'organization_id' => build_column(column_type: 'Number'),
                'organization' => build_many_to_one(foreign_collection: 'organizations', foreign_key: 'organization_id')
              }
            }
          ),
          build_collection(
            name: 'organizations',
            schema: {
              fields: {
                'id' => build_numeric_primary_key,
                'name' => build_column(column_type: 'String'),
                'tier' => build_column(column_type: 'String')
              }
            }
          ),
          build_collection(
            name: 'holders',
            schema: {
              fields: {
                'id' => build_numeric_primary_key,
                'national_id' => build_column(column_type: 'String'),
                'region' => build_column(column_type: 'String')
              }
            }
          )
        ]
      end

      let(:scopes) do
        {
          'accounts' => Nodes::ConditionTreeLeaf.new('organization:name', Operators::EQUAL, 'OwnOrg'),
          'holders' => Nodes::ConditionTreeLeaf.new('region', Operators::EQUAL, 'EU')
        }
      end

      let(:permissions) do
        permissions = described_class.new(caller)
        allow(permissions).to receive(:get_scope_for_related_records) { |collection| scopes[collection.name] }

        permissions
      end

      # What each related collection's own scoped query returns: the keys its scope keeps.
      let(:in_scope_keys) { { 'accounts' => [10, 30], 'holders' => [100], 'organizations' => [] } }

      before do
        in_scope_keys.each_key do |name|
          allow(datasource.get_collection(name)).to receive(:list) { in_scope_keys[name].map { |id| { 'id' => id } } }
        end
      end

      let(:cards_records) do
        [
          { 'id' => 1, 'account' => { 'id' => 10, 'iban' => 'FR76' }, 'holder' => { 'id' => 100, 'national_id' => 'EU-1' } },
          { 'id' => 2, 'account' => { 'id' => 20, 'iban' => 'DE22' }, 'holder' => { 'id' => 100, 'national_id' => 'EU-1' } },
          { 'id' => 3, 'account' => { 'id' => 30, 'iban' => 'FR14' }, 'holder' => { 'id' => 300, 'national_id' => 'US-3' } },
          { 'id' => 4, 'account' => nil, 'holder' => { 'id' => 100, 'national_id' => 'EU-1' } }
        ]
      end

      let(:projection) { Projection.new(%w[id account:iban holder:national_id]) }

      describe '#get_scope_for_related_records' do
        let(:permissions) { described_class.new(caller) }
        let(:accounts) { datasource.get_collection('accounts') }

        before { allow(permissions).to receive(:get_scope).and_return(scopes['accounts']) }

        it 'returns the scope when the server flags it as applying to related records' do
          allow(permissions).to receive(:get_rendering_data).and_return({ related_record_scopes: [:accounts] })

          expect(permissions.get_scope_for_related_records(accounts)).to eq(scopes['accounts'])
        end

        it 'returns nil when the server does not flag the scope' do
          allow(permissions).to receive(:get_rendering_data).and_return({ related_record_scopes: [] })

          expect(permissions.get_scope_for_related_records(accounts)).to be_nil
        end
      end

      describe '#relation_scopes' do
        it 'asks for the related scope of every collection the projection reaches through a relation' do
          fetched = []
          allow(permissions).to receive(:get_scope_for_related_records) { |collection| fetched << collection.name and nil }

          permissions.relation_scopes(cards, Projection.new(%w[id account:organization:name holder:national_id]))

          expect(fetched).to contain_exactly('accounts', 'organizations', 'holders')
        end

        it 'asks for no scope when the projection reaches no relation' do
          fetched = []
          allow(permissions).to receive(:get_scope_for_related_records) { |collection| fetched << collection.name and nil }

          permissions.relation_scopes(cards, Projection.new(%w[id]))

          expect(fetched).to be_empty
        end

        it 'adds the primary key of each scoped related record, nested under its relation' do
          relation_scopes = permissions.relation_scopes(cards, projection)

          expect(relation_scopes.with_scope_fields(projection)).to eq(
            %w[id account:iban holder:national_id account:id holder:id]
          )
        end

        it 'checks the related records with one query on their collection, under its scope' do
          relation_scopes = permissions.relation_scopes(cards, projection)

          relation_scopes.redact(cards_records, projection)

          expect(datasource.get_collection('accounts')).to have_received(:list) do |list_caller, filter, list_projection|
            expect(list_caller).to eq(caller)
            expect(filter.condition_tree.to_h).to eq(
              {
                aggregator: 'And',
                conditions: [
                  { field: 'organization:name', operator: Operators::EQUAL, value: 'OwnOrg' },
                  { field: 'id', operator: Operators::IN, value: [10, 20, 30] }
                ]
              }
            )
            expect(list_projection).to eq(%w[id])
          end
        end

        it 'keeps every card and empties the related records outside their scope' do
          relation_scopes = permissions.relation_scopes(cards, projection)

          expect(relation_scopes.redact(cards_records, projection)).to eq(
            [
              { 'id' => 1, 'account' => { 'iban' => 'FR76' }, 'holder' => { 'national_id' => 'EU-1' } },
              { 'id' => 2, 'account' => nil, 'holder' => { 'national_id' => 'EU-1' } },
              { 'id' => 3, 'account' => { 'iban' => 'FR14' }, 'holder' => nil },
              { 'id' => 4, 'account' => nil, 'holder' => { 'national_id' => 'EU-1' } }
            ]
          )
        end

        it 'empties a record reached through several relations' do
          scopes['organizations'] = Nodes::ConditionTreeLeaf.new('tier', Operators::EQUAL, 'gold')
          scopes.delete('accounts')
          in_scope_keys['organizations'] = [1]
          deep_projection = Projection.new(%w[id account:organization:name])
          relation_scopes = permissions.relation_scopes(cards, deep_projection)
          records = [
            { 'id' => 1, 'account' => { 'organization' => { 'id' => 1, 'name' => 'OwnOrg' } } },
            { 'id' => 2, 'account' => { 'organization' => { 'id' => 2, 'name' => 'OwnOrg' } } }
          ]

          expect(relation_scopes.redact(records, deep_projection)).to eq(
            [
              { 'id' => 1, 'account' => { 'organization' => { 'name' => 'OwnOrg' } } },
              { 'id' => 2, 'account' => { 'organization' => nil } }
            ]
          )
        end

        it 'returns the records untouched and queries nothing when no relation is scoped' do
          scopes.clear
          relation_scopes = permissions.relation_scopes(cards, projection)

          expect(relation_scopes.redact(cards_records, projection)).to be(cards_records)
          expect(datasource.get_collection('accounts')).not_to have_received(:list)
        end
      end
    end
  end
end
