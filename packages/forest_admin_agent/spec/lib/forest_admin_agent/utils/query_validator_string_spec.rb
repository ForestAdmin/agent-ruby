require 'spec_helper'

module ForestAdminAgent
  module Utils
    include ForestAdminDatasourceToolkit::Exceptions
    describe QueryValidator do
      describe 'string sanitization edge cases' do
        context 'escaped quotes' do
          it 'handles escaped single quotes' do
            query = "SELECT * FROM users WHERE name='test\\'test'"
            expect { described_class.valid?(query) }.not_to raise_error
          end

          it 'handles escaped double quotes' do
            query = 'SELECT * FROM users WHERE name="test\\"test"'
            expect { described_class.valid?(query) }.not_to raise_error
          end
        end

        context 'SQL comment edge cases' do
          it 'allows -- inside single quotes' do
            query = "SELECT * FROM users WHERE comment='test -- comment'"
            expect { described_class.valid?(query) }.not_to raise_error
          end

          it 'allows -- outside quotes as SQL comment' do
            query = 'SELECT * FROM users -- this is a comment'
            expect { described_class.valid?(query) }.not_to raise_error
          end

          it 'allows /* */ style comments' do
            query = 'SELECT * FROM /* comment */ users'
            expect { described_class.valid?(query) }.not_to raise_error
          end
        end

        context 'forbidden keyword in comments' do
          it 'removes DROP in SQL comment (security fix)' do
            query = 'SELECT * FROM users -- DROP TABLE users'
            # Comments are now stripped before validation to prevent comment-based bypasses
            # The query becomes "SELECT * FROM users " which is valid
            expect { described_class.valid?(query) }.not_to raise_error
          end

          it 'removes forbidden keyword in /* */ comment (security fix)' do
            query = 'SELECT * FROM users /* DROP TABLE */ WHERE id=1'
            # Comments are now stripped before validation
            # The query becomes "SELECT * FROM users  WHERE id=1" which is valid
            expect { described_class.valid?(query) }.not_to raise_error
          end
        end
      end
    end
  end
end
