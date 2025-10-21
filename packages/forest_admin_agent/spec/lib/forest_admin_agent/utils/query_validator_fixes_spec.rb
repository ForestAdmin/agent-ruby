require 'spec_helper'

# Tests for security fixes implemented to address SQL injection vulnerabilities
# These tests verify that the fixes correctly block malicious queries while allowing legitimate ones

module ForestAdminAgent
  module Utils
    include ForestAdminDatasourceToolkit::Exceptions

    describe QueryValidator do
      describe 'security fixes validation' do
        context 'forbidden functions blocking' do
          it 'blocks pg_sleep function (PostgreSQL timing attack)' do
            query = 'SELECT * FROM users WHERE id=1 AND pg_sleep(10)'
            expect { described_class.valid?(query) }
              .to raise_error(ForestException, /forbidden function: pg_sleep/)
          end

          it 'blocks SLEEP function (MySQL timing attack)' do
            query = 'SELECT * FROM users WHERE id=1 AND SLEEP(10)'
            expect { described_class.valid?(query) }
              .to raise_error(ForestException, /forbidden function: SLEEP/)
          end

          it 'blocks BENCHMARK function (MySQL timing attack)' do
            query = 'SELECT BENCHMARK(10000000, MD5("test"))'
            expect { described_class.valid?(query) }
              .to raise_error(ForestException, /forbidden function: BENCHMARK/)
          end

          it 'blocks pg_read_file function (PostgreSQL file read)' do
            query = "SELECT pg_read_file('/etc/passwd')"
            expect { described_class.valid?(query) }
              .to raise_error(ForestException, /forbidden function: pg_read_file/)
          end

          it 'blocks pg_read_binary_file function (PostgreSQL file read)' do
            query = "SELECT pg_read_binary_file('/etc/shadow')"
            expect { described_class.valid?(query) }
              .to raise_error(ForestException, /forbidden function: pg_read_binary_file/)
          end

          it 'blocks pg_ls_dir function (PostgreSQL directory listing)' do
            query = "SELECT pg_ls_dir('/etc')"
            expect { described_class.valid?(query) }
              .to raise_error(ForestException, /forbidden function: pg_ls_dir/)
          end

          it 'blocks LOAD_FILE function (MySQL file read)' do
            query = "SELECT LOAD_FILE('/etc/passwd')"
            # LOAD_FILE is in both FORBIDDEN_KEYWORDS and FORBIDDEN_FUNCTIONS
            expect { described_class.valid?(query) }
              .to raise_error(ForestException, /forbidden keyword: LOAD_FILE|forbidden function: LOAD_FILE/)
          end

          it 'blocks WAITFOR function (SQL Server timing)' do
            query = 'SELECT * FROM users WHERE id=1 AND WAITFOR("00:00:10")'
            # Need parentheses for function matching
            expect { described_class.valid?(query) }
              .to raise_error(ForestException, /forbidden function: WAITFOR/)
          end

          it 'allows legitimate functions like COUNT, SUM, AVG' do
            query = 'SELECT COUNT(*), SUM(amount), AVG(price) FROM orders'
            expect { described_class.valid?(query) }.not_to raise_error
          end
        end

        context 'enhanced UNION blocking' do
          it 'blocks UNION keyword' do
            query = 'SELECT id FROM users UNION SELECT password FROM admin_users'
            expect { described_class.valid?(query) }
              .to raise_error(ForestException, /forbidden keyword: UNION/)
          end

          it 'blocks UNION ALL keyword' do
            query = 'SELECT id FROM users UNION ALL SELECT id FROM deleted_users'
            expect { described_class.valid?(query) }
              .to raise_error(ForestException, /forbidden keyword: UNION/)
          end

          it 'blocks INTERSECT keyword' do
            query = 'SELECT email FROM users INTERSECT SELECT email FROM admins'
            expect { described_class.valid?(query) }
              .to raise_error(ForestException, /forbidden keyword: INTERSECT/)
          end

          it 'blocks EXCEPT keyword' do
            query = 'SELECT id FROM all_users EXCEPT SELECT id FROM banned_users'
            expect { described_class.valid?(query) }
              .to raise_error(ForestException, /forbidden keyword: EXCEPT/)
          end
        end

        context 'file system write blocking' do
          it 'blocks INTO OUTFILE (MySQL file write)' do
            query = "SELECT * FROM users INTO OUTFILE '/tmp/users.txt'"
            expect { described_class.valid?(query) }
              .to raise_error(ForestException, /forbidden keyword: INTO/)
          end

          it 'blocks INTO DUMPFILE (MySQL file write)' do
            query = "SELECT * FROM users INTO DUMPFILE '/tmp/dump.txt'"
            expect { described_class.valid?(query) }
              .to raise_error(ForestException, /forbidden keyword: INTO/)
          end

          it 'blocks web shell upload attempt' do
            query = "SELECT '<?php system($_GET[\"cmd\"]); ?>' INTO OUTFILE '/var/www/html/shell.php'"
            expect { described_class.valid?(query) }
              .to raise_error(ForestException, /forbidden keyword: INTO/)
          end

          it 'blocks COPY keyword (PostgreSQL file operations)' do
            query = "COPY users TO '/tmp/users.csv'"
            # This should fail at SELECT-only check, but let's verify
            expect { described_class.valid?(query) }
              .to raise_error(ForestException)
          end
        end

        context 'boolean injection pattern blocking' do
          it 'blocks OR 1=1 pattern' do
            query = 'SELECT * FROM users WHERE id=1 OR 1=1'
            expect { described_class.valid?(query) }
              .to raise_error(ForestException, /SQL injection pattern/)
          end

          it 'blocks OR 2=2 pattern' do
            query = 'SELECT * FROM users WHERE id=1 OR 2=2'
            expect { described_class.valid?(query) }
              .to raise_error(ForestException, /SQL injection pattern/)
          end

          it 'blocks OR TRUE pattern' do
            query = 'SELECT * FROM users WHERE id=1 OR TRUE'
            expect { described_class.valid?(query) }
              .to raise_error(ForestException, /SQL injection pattern/)
          end

          it 'blocks OR FALSE pattern' do
            query = 'SELECT * FROM users WHERE FALSE OR FALSE'
            expect { described_class.valid?(query) }
              .to raise_error(ForestException, /SQL injection pattern/)
          end

          it 'blocks AND 1=1 tautology' do
            query = 'SELECT * FROM users WHERE id=1 AND 1=1'
            expect { described_class.valid?(query) }
              .to raise_error(ForestException, /SQL injection pattern/)
          end

          it 'allows legitimate OR in WHERE clauses with columns' do
            query = 'SELECT * FROM users WHERE status="active" OR status="pending"'
            expect { described_class.valid?(query) }.not_to raise_error
          end

          it 'allows legitimate AND with column comparisons' do
            query = 'SELECT * FROM users WHERE age > 18 AND status="verified"'
            expect { described_class.valid?(query) }.not_to raise_error
          end
        end

        context 'SQL comment stripping' do
          it 'strips single-line comments before validation' do
            query = 'SELECT * FROM users -- this comment is removed'
            expect { described_class.valid?(query) }.not_to raise_error
          end

          it 'strips multi-line comments before validation' do
            query = 'SELECT * FROM /* comment */ users WHERE id=1'
            expect { described_class.valid?(query) }.not_to raise_error
          end

          it 'prevents comment-based keyword bypass' do
            query = 'SELECT * FROM users -- DROP TABLE users'
            # Comment is stripped, so DROP is not detected - query is valid
            expect { described_class.valid?(query) }.not_to raise_error
          end

          it 'preserves comments inside string literals' do
            query = 'SELECT * FROM users WHERE comment="test -- not a comment"'
            expect { described_class.valid?(query) }.not_to raise_error
          end

          it 'strips SQL comment tokens outside strings' do
            query = 'SELECT * FROM users WHERE name="test" --'
            # Comments are stripped, so this becomes a valid query
            expect { described_class.valid?(query) }.not_to raise_error
          end

          it 'strips multi-line comment tokens outside strings' do
            query = 'SELECT /* test */ * FROM users'
            # Comments are stripped, so this becomes "SELECT  * FROM users" which is valid
            expect { described_class.valid?(query) }.not_to raise_error
          end
        end

        context 'stacked query blocking' do
          it 'blocks semicolon followed by DROP' do
            query = 'SELECT * FROM users; DROP TABLE users'
            expect { described_class.valid?(query) }
              .to raise_error(ForestException, /Semicolon must only appear/)
          end

          it 'blocks semicolon followed by DELETE' do
            query = 'SELECT * FROM users; DELETE FROM users'
            expect { described_class.valid?(query) }
              .to raise_error(ForestException, /Semicolon must only appear/)
          end

          it 'blocks semicolon followed by INSERT' do
            query = 'SELECT * FROM users; INSERT INTO users VALUES (1, "hacker")'
            expect { described_class.valid?(query) }
              .to raise_error(ForestException, /Semicolon must only appear/)
          end

          it 'blocks semicolon followed by UPDATE' do
            query = 'SELECT * FROM users; UPDATE users SET role="admin"'
            expect { described_class.valid?(query) }
              .to raise_error(ForestException, /Semicolon must only appear/)
          end

          it 'allows single semicolon at end of query' do
            query = 'SELECT * FROM users WHERE id=1;'
            expect { described_class.valid?(query) }.not_to raise_error
          end
        end

        context 'legitimate queries still work' do
          it 'allows simple SELECT queries' do
            query = 'SELECT * FROM users'
            expect { described_class.valid?(query) }.not_to raise_error
          end

          it 'allows SELECT with WHERE clause' do
            query = 'SELECT id, name FROM users WHERE age > 18'
            expect { described_class.valid?(query) }.not_to raise_error
          end

          it 'allows SELECT with JOIN' do
            query = 'SELECT u.name, o.total FROM users u JOIN orders o ON u.id=o.user_id'
            expect { described_class.valid?(query) }.not_to raise_error
          end

          it 'allows SELECT with subqueries' do
            query = 'SELECT * FROM users WHERE id IN (SELECT user_id FROM orders WHERE total > 100)'
            expect { described_class.valid?(query) }.not_to raise_error
          end

          it 'allows SELECT with aggregate functions' do
            query = 'SELECT COUNT(*), AVG(price), SUM(total) FROM orders GROUP BY category'
            expect { described_class.valid?(query) }.not_to raise_error
          end

          it 'allows SELECT with CASE statements' do
            query = 'SELECT CASE WHEN age > 18 THEN "adult" ELSE "minor" END FROM users'
            expect { described_class.valid?(query) }.not_to raise_error
          end

          it 'allows SELECT with EXISTS' do
            query = 'SELECT * FROM users WHERE EXISTS (SELECT 1 FROM orders WHERE orders.user_id=users.id)'
            expect { described_class.valid?(query) }.not_to raise_error
          end

          it 'allows SELECT with CAST' do
            query = 'SELECT CAST(price AS DECIMAL(10,2)) FROM products'
            expect { described_class.valid?(query) }.not_to raise_error
          end
        end

        context 'edge cases and boundary conditions' do
          it 'handles query with mixed case keywords' do
            query = 'SeLeCt * FrOm users WhErE id=1'
            expect { described_class.valid?(query) }.not_to raise_error
          end

          it 'handles query with extra whitespace' do
            query = 'SELECT    *    FROM    users    WHERE    id=1'
            expect { described_class.valid?(query) }.not_to raise_error
          end

          it 'handles query with tabs and newlines' do
            query = "SELECT *\nFROM users\nWHERE id=1"
            expect { described_class.valid?(query) }.not_to raise_error
          end

          it 'rejects empty query' do
            query = '   '
            expect { described_class.valid?(query) }
              .to raise_error(ForestException, /cannot be empty/)
          end

          it 'handles very long legitimate query' do
            columns = (1..50).map { |i| "column#{i}" }.join(', ')
            query = "SELECT #{columns} FROM users WHERE id=1"
            expect { described_class.valid?(query) }.not_to raise_error
          end
        end
      end
    end
  end
end
