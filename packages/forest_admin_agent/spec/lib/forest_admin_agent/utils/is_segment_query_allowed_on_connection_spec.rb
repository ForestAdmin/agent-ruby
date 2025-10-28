require 'spec_helper'

module ForestAdminAgent
  module Utils
    describe IsSegmentQueryAllowedOnConnection do
      describe '.allowed?' do
        context 'when there are no permissions' do
          it 'returns false' do
            permissions = {}
            expect(described_class.allowed?(permissions, '', '')).to be false
          end

          it 'returns false when liveQuerySegments is nil' do
            permissions = { liveQuerySegments: nil }
            expect(described_class.allowed?(permissions, '', '')).to be false
          end

          it 'returns false when connection_name is nil' do
            permissions = { liveQuerySegments: [] }
            expect(described_class.allowed?(permissions, 'SELECT * FROM users', nil)).to be false
          end

          it 'returns false when connection_name is empty' do
            permissions = { liveQuerySegments: [] }
            expect(described_class.allowed?(permissions, 'SELECT * FROM users', '')).to be false
          end
        end

        context 'when there are multiple queries (UNION)' do
          it 'authorizes the query if every subquery is allowed' do
            permissions = {
              liveQuerySegments: [
                {
                  query: 'SELECT * from users;',
                  connectionName: 'main'
                },
                {
                  query: 'SELECT * from admins;',
                  connectionName: 'main'
                }
              ]
            }
            expect(
              described_class.allowed?(
                permissions,
                'SELECT * from users /*MULTI-SEGMENTS-QUERIES-UNION*/ UNION SELECT * from admins',
                'main'
              )
            ).to be true
          end

          it 'rejects the query if one subquery is not allowed' do
            permissions = {
              liveQuerySegments: [
                {
                  query: 'SELECT * from users;',
                  connectionName: 'main'
                }
              ]
            }
            expect(
              described_class.allowed?(
                permissions,
                'SELECT * from users /*MULTI-SEGMENTS-QUERIES-UNION*/ UNION SELECT * from admins',
                'main'
              )
            ).to be false
          end

          it 'rejects if the queries are not on the same connectionName' do
            permissions = {
              liveQuerySegments: [
                {
                  query: 'SELECT * from users;',
                  connectionName: 'main'
                },
                {
                  query: 'SELECT * from admins;',
                  connectionName: 'secondary'
                }
              ]
            }
            expect(
              described_class.allowed?(
                permissions,
                'SELECT * from users /*MULTI-SEGMENTS-QUERIES-UNION*/ UNION SELECT * from admins',
                'main'
              )
            ).to be false
          end
        end

        context 'when there is only one query' do
          it 'returns true if the query is allowed' do
            permissions = {
              liveQuerySegments: [
                {
                  query: 'SELECT * from users;',
                  connectionName: 'main'
                }
              ]
            }
            expect(described_class.allowed?(permissions, 'SELECT * from users;', 'main')).to be true
          end

          it 'returns false if the query is not allowed' do
            permissions = {
              liveQuerySegments: [
                {
                  query: 'SELECT * from admins;',
                  connectionName: 'main'
                }
              ]
            }
            expect(described_class.allowed?(permissions, 'SELECT * from users;', 'main')).to be false
          end

          it 'returns false if the connection name does not match' do
            permissions = {
              liveQuerySegments: [
                {
                  query: 'SELECT * from users;',
                  connectionName: 'main'
                }
              ]
            }
            expect(described_class.allowed?(permissions, 'SELECT * from users;', 'secondary')).to be false
          end
        end
      end
    end
  end
end
