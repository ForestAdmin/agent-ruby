require 'spec_helper'
require 'timeout'

module ForestAdminAgent
  module Utils
    describe ContextVariablesInjector do
      let(:team) { { 'id' => 100, 'name' => 'Ninja' } }

      let(:user) do
        {
          'id' => 1,
          'firstName' => 'John',
          'lastName' => 'Doe',
          'fullName' => 'John Doe',
          'email' => 'john.doe@domain.com',
          'tags' => { 'planet' => 'Death Star' },
          'roleId' => 1,
          'permissionLevel' => 'admin'
        }
      end

      let(:context_variables) do
        ForestAdminAgent::Utils::ContextVariables.new(
          team,
          user,
          {
            'siths.selectedRecord.rank' => 3,
            'siths.selectedRecord.power' => 'electrocute',
            'siths.selectedRecord.ids' => [1, 2, 3],
            'siths.selectedRecord.path' => 'C:\\eyes-of-the-dark',
            'siths.selectedRecord.tricky' => [{ 'note' => 'looks like {{currentUser.id}} but is not' }],
            'siths.selectedRecord.selfref' => [{ 'note' => 'ref: {{siths.selectedRecord.selfref}}' }]
          }
        )
      end

      context 'when inject_context_in_filter is called' do
        it 'returns it as it is with a number' do
          result = described_class.inject_context_in_value_custom(8) { {} }

          expect(result).to eq(8)
        end

        it 'returns it as it is with a array' do
          value = ['test', 'me']
          result = described_class.inject_context_in_value_custom(value) { {} }

          expect(result).to eq(value)
        end

        it 'replaces all variables with a string' do
          replace_function = ->(key) { key.split('.').pop.upcase }
          result = described_class.inject_context_in_value_custom(
            'It should be {{siths.selectedRecord.power}} of rank {{siths.selectedRecord.rank}}. But {{siths.selectedRecord.power}} can be duplicated.'
          ) do |key|
            replace_function.call(key)
          end

          expect(result).to eq('It should be POWER of rank RANK. But POWER can be duplicated.')
        end
      end

      context('when inject_context_in_value is called') do
        it 'returns it as it is with a number' do
          result = described_class.inject_context_in_value(8, context_variables)

          expect(result).to eq(8)
        end

        it 'returns it as it is with a array' do
          value = ['test', 'me']
          result = described_class.inject_context_in_value(value, context_variables)

          expect(result).to eq(value)
        end

        it 'replaces all variables with a string' do
          first_value_part = 'It should be {{siths.selectedRecord.power}} of rank {{siths.selectedRecord.rank}}.'
          second_value_part = 'But {{siths.selectedRecord.power}} can be duplicated.'
          result = described_class.inject_context_in_value(
            "#{first_value_part} #{second_value_part}",
            context_variables
          )

          expect(result).to eq('It should be electrocute of rank 3. But electrocute can be duplicated.')
        end

        it 'replaces all currentUser variables' do
          [
            { key: 'email', expected_value: user['email'] },
            { key: 'firstName', expected_value: user['firstName'] },
            { key: 'lastName', expected_value: user['lastName'] },
            { key: 'fullName', expected_value: user['fullName'] },
            { key: 'id', expected_value: user['id'] },
            { key: 'permissionLevel', expected_value: user['permissionLevel'] },
            { key: 'roleId', expected_value: user['roleId'] },
            { key: 'tags.planet', expected_value: user['tags']['planet'] },
            { key: 'team.id', expected_value: team['id'] },
            { key: 'team.name', expected_value: team['name'] }
          ].each do |value|
            key = value[:key]
            expected_value = value[:expected_value]
            expect(
              described_class.inject_context_in_value(
                "{{currentUser.#{key}}}",
                context_variables
              )
            ).to eq(expected_value)
          end
        end

        it 'returns the resolved object as-is when the value is exactly one reference, instead of a serialized string' do
          result = described_class.inject_context_in_value('{{currentUser.tags}}', context_variables)

          expect(result).to eq(user['tags'])
          expect(result).to be_a(Hash)
        end

        it 'returns a resolved array as-is when the value is exactly one reference' do
          result = described_class.inject_context_in_value('{{siths.selectedRecord.ids}}', context_variables)

          expect(result).to eq([1, 2, 3])
          expect(result).to be_an(Array)
        end

        it 'still serializes an Array/Hash value to JSON when the reference is embedded in a larger string' do
          result = described_class.inject_context_in_value('tags: {{currentUser.tags}}', context_variables)

          expect(result).to eq("tags: #{user["tags"].to_json}")
        end

        it 'does not corrupt backslashes when substituting a value embedded in a larger string' do
          result = described_class.inject_context_in_value('path: {{siths.selectedRecord.path}}', context_variables)

          expect(result).to eq('path: C:\eyes-of-the-dark')
        end

        it 'does not re-interpret "{{...}}"-looking text inside a resolved value as a new reference' do
          expected_json = [{ 'note' => 'looks like {{currentUser.id}} but is not' }].to_json

          result = Timeout.timeout(2) do
            described_class.inject_context_in_value('leaked: {{siths.selectedRecord.tricky}}', context_variables)
          end

          expect(result).to eq("leaked: #{expected_json}")
        end

        it 'does not hang when a resolved value contains a literal reference to its own key' do
          expected_json = [{ 'note' => 'ref: {{siths.selectedRecord.selfref}}' }].to_json

          result = Timeout.timeout(2) do
            described_class.inject_context_in_value('self: {{siths.selectedRecord.selfref}}', context_variables)
          end

          expect(result).to eq("self: #{expected_json}")
        end
      end

      context('when inject_context_in_native_query is called') do
        let(:datasource) do
          datasource = instance_double(ForestAdminDatasourceToolkit::Datasource)
          allow(datasource).to receive(:build_binding_symbol) { |_connection_name, binds| "$#{binds.size + 1}" }
          datasource
        end
        let(:connection_name) { 'primary' }

        it 'returns the query unchanged with an empty binds hash when there is no placeholder' do
          result = described_class.inject_context_in_native_query(
            datasource, connection_name, 'SELECT * FROM users;', context_variables
          )

          expect(result).to eq(['SELECT * FROM users;', {}])
        end

        it 'returns non-String query input untouched' do
          result = described_class.inject_context_in_native_query(datasource, connection_name, 8, context_variables)

          expect(result).to eq(8)
        end

        it 'dedupes repeated occurrences of the same key to a single bind symbol' do
          query = 'SELECT * FROM users WHERE id = {{siths.selectedRecord.rank}} OR id = {{siths.selectedRecord.rank}};'

          query_result, binds = described_class.inject_context_in_native_query(
            datasource, connection_name, query, context_variables
          )

          expect(query_result).to eq('SELECT * FROM users WHERE id = $1 OR id = $1;')
          expect(binds).to eq({ '$1' => 3 })
        end

        it 'assigns sequential bind symbols to distinct keys in first-occurrence order' do
          query = 'SELECT * FROM users WHERE rank = {{siths.selectedRecord.rank}} ' \
                  'AND power = {{siths.selectedRecord.power}};'

          query_result, binds = described_class.inject_context_in_native_query(
            datasource, connection_name, query, context_variables
          )

          expect(query_result).to eq('SELECT * FROM users WHERE rank = $1 AND power = $2;')
          expect(binds).to eq({ '$1' => 3, '$2' => 'electrocute' })
        end

        it 'does not hang when a resolved value happens to equal the literal name of another key' do
          tricky_context_variables = ForestAdminAgent::Utils::ContextVariables.new(
            team,
            user,
            {
              'siths.selectedRecord.alias' => 'siths.selectedRecord.rank',
              'siths.selectedRecord.rank' => 3
            }
          )
          query = 'SELECT * FROM users WHERE a = {{siths.selectedRecord.alias}} ' \
                  'AND b = {{siths.selectedRecord.rank}};'

          query_result, binds = Timeout.timeout(2) do
            described_class.inject_context_in_native_query(
              datasource, connection_name, query, tricky_context_variables
            )
          end

          expect(query_result).to eq('SELECT * FROM users WHERE a = $1 AND b = $2;')
          expect(binds).to eq({ '$1' => 'siths.selectedRecord.rank', '$2' => 3 })
        end
      end
    end
  end
end
