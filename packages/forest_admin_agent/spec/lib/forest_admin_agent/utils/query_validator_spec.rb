require 'spec_helper'

module ForestAdminAgent
  module Utils
    include ForestAdminDatasourceToolkit::Exceptions
    describe QueryValidator do
      describe 'valid queries' do
        it 'allows a simple SELECT query' do
          query = 'SELECT * FROM users;'
          expect(described_class).to be_valid(query)
        end

        it 'allows a query with a WHERE clause containing parentheses' do
          query = "SELECT * FROM users WHERE (id > 1 AND name = 'John');"
          expect(described_class).to be_valid(query)
        end

        it 'allows balanced parentheses in subqueries' do
          query = 'SELECT * FROM (SELECT id FROM users) AS subquery;'
          expect(described_class).to be_valid(query)
        end

        it 'allows a query with a subquery using the IN clause' do
          query = 'SELECT id, name FROM users WHERE id IN (SELECT user_id FROM orders WHERE total > 100);'
          expect(described_class).to be_valid(query)
        end

        it 'allows a query without a semicolon when semicolon is not required' do
          query = 'SELECT name FROM users'
          expect(described_class).to be_valid(query)
        end

        it 'does not raise an error for a semicolon inside a string in the WHERE clause' do
          query = 'SELECT * FROM users WHERE name = "test;";'
          expect { described_class.valid?(query) }.not_to raise_error
        end

        it 'does not raise an error for a parenthesis inside a string in the WHERE clause' do
          query = 'SELECT * FROM users WHERE name = "(test)";'
          expect { described_class.valid?(query) }.not_to raise_error
        end

        it 'allows a query with a lowercase SELECT' do
          query = "select * from users WHERE username = 'admin';"
          expect { described_class.valid?(query) }.not_to raise_error
        end
      end

      describe 'queries that raise exceptions' do
        it 'raises an error for an empty query' do
          query = '   '
          expect { described_class.valid?(query) }.to raise_error(ForestException, 'Query cannot be empty.')
        end

        it 'raises an error for non-SELECT queries' do
          query = 'DELETE FROM users;'
          expect { described_class.valid?(query) }.to raise_error(ForestException, 'Only SELECT queries are allowed.')
        end

        it 'raises an error for multiple queries' do
          query = 'SELECT * FROM users; SELECT * FROM orders;'
          expect { described_class.valid?(query) }.to raise_error(ForestException, 'Only one query is allowed.')
        end

        it 'raises an error for unbalanced parentheses outside WHERE clause' do
          query = 'SELECT (id, name FROM users WHERE (id > 1);'
          expect { described_class.valid?(query) }.to raise_error(ForestException, 'The query contains unbalanced parentheses.')
        end

        it 'raises an error for a semicolon not at the end of the query' do
          query = 'SELECT * FROM users; WHERE id > 1'
          expect { described_class.valid?(query) }.to raise_error(ForestException, 'Semicolon must only appear as the last character in the query.')
        end

        it 'raises an error for forbidden keywords even inside subqueries' do
          query = 'SELECT * FROM users WHERE id IN (DROP TABLE users);'
          expect { described_class.valid?(query) }.to raise_error(ForestException, 'The query contains forbidden keyword: DROP.')
        end

        it 'raises an error for unbalanced parentheses in subqueries' do
          query = 'SELECT * FROM (SELECT id, name FROM users WHERE id > 1;'
          expect { described_class.valid?(query) }.to raise_error(ForestException, 'The query contains unbalanced parentheses.')
        end

        it 'raises an error for an OR-based injection' do
          query = "SELECT * FROM users WHERE username = 'admin' OR 1=1;"
          expect { described_class.valid?(query) }
            .to raise_error(ForestException, 'The query contains a potential SQL injection pattern.')
        end
      end
    end
  end
end
