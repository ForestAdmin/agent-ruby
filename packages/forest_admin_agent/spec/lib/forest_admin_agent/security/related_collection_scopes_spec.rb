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
        allow(permissions).to receive(:get_scope) { |collection| scopes[collection.name] }

        permissions
      end

      let(:cards_records) do
        [
          { 'id' => 1, 'account' => { 'id' => 10, 'iban' => 'FR76', 'organization' => { 'name' => 'OwnOrg' } },
            'holder' => { 'id' => 100, 'national_id' => 'EU-1', 'region' => 'EU' } },
          { 'id' => 2, 'account' => { 'id' => 20, 'iban' => 'DE22', 'organization' => { 'name' => 'AnotherTenant' } },
            'holder' => { 'id' => 100, 'national_id' => 'EU-1', 'region' => 'EU' } },
          { 'id' => 3, 'account' => { 'id' => 30, 'iban' => 'FR14', 'organization' => { 'name' => 'OwnOrg' } },
            'holder' => { 'id' => 300, 'national_id' => 'US-3', 'region' => 'US' } },
          { 'id' => 4, 'account' => nil,
            'holder' => { 'id' => 100, 'national_id' => 'EU-1', 'region' => 'EU' } }
        ]
      end

      let(:projection) { Projection.new(%w[id account:id account:iban holder:id holder:national_id]) }

      describe '#relation_scopes' do
        it 'fetches the scope of every collection the projection reaches through a relation' do
          fetched = []
          allow(permissions).to receive(:get_scope) { |collection| fetched << collection.name and nil }

          permissions.relation_scopes(cards, Projection.new(%w[id account:organization:name holder:national_id]))

          expect(fetched).to contain_exactly('accounts', 'organizations', 'holders')
        end

        it 'fetches no scope when the projection reaches no relation' do
          fetched = []
          allow(permissions).to receive(:get_scope) { |collection| fetched << collection.name and nil }

          permissions.relation_scopes(cards, Projection.new(%w[id]))

          expect(fetched).to be_empty
        end

        it 'adds the fields each scope reads, nested under its relation' do
          relation_scopes = permissions.relation_scopes(cards, projection)

          expect(relation_scopes.with_scope_fields(projection)).to eq(
            %w[id account:id account:iban holder:id holder:national_id account:organization:name holder:region]
          )
        end

        it 'keeps every card and empties the related records outside their scope' do
          relation_scopes = permissions.relation_scopes(cards, projection)

          expect(relation_scopes.redact(cards_records, projection, 'Europe/Paris')).to eq(
            [
              { 'id' => 1, 'account' => { 'id' => 10, 'iban' => 'FR76' },
                'holder' => { 'id' => 100, 'national_id' => 'EU-1' } },
              { 'id' => 2, 'account' => nil, 'holder' => { 'id' => 100, 'national_id' => 'EU-1' } },
              { 'id' => 3, 'account' => { 'id' => 30, 'iban' => 'FR14' }, 'holder' => nil },
              { 'id' => 4, 'account' => nil, 'holder' => { 'id' => 100, 'national_id' => 'EU-1' } }
            ]
          )
        end

        it 'empties a record reached through several relations' do
          scopes['organizations'] = Nodes::ConditionTreeLeaf.new('tier', Operators::EQUAL, 'gold')
          scopes.delete('accounts')
          deep_projection = Projection.new(%w[id account:organization:name])
          relation_scopes = permissions.relation_scopes(cards, deep_projection)
          records = [
            { 'id' => 1, 'account' => { 'organization' => { 'name' => 'OwnOrg', 'tier' => 'gold' } } },
            { 'id' => 2, 'account' => { 'organization' => { 'name' => 'OwnOrg', 'tier' => 'silver' } } }
          ]

          expect(relation_scopes.redact(records, deep_projection, 'Europe/Paris')).to eq(
            [
              { 'id' => 1, 'account' => { 'organization' => { 'name' => 'OwnOrg' } } },
              { 'id' => 2, 'account' => { 'organization' => nil } }
            ]
          )
        end

        it 'returns the records untouched when no relation is scoped' do
          scopes.clear
          relation_scopes = permissions.relation_scopes(cards, projection)

          expect(relation_scopes.redact(cards_records, projection, 'Europe/Paris')).to be(cards_records)
        end
      end
    end
  end
end
