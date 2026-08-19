require 'spec_helper'

module ForestAdminAgent
  module AuditTrail
    module Sql
      # The store specs exercise this against SQLite; these pin the SQL for the adapters no local database
      # covers, and the two properties that matter whatever the dialect.
      describe TextSearch do
        let(:adapters) { %w[PostgreSQL SQLite Mysql2] }
        let(:searched_columns) { %w[action_name user_first_name user_last_name user_email] }

        def filter_for(adapter)
          # rubocop:disable RSpec/VerifiedDoubles
          connection = double(adapter.to_s, adapter_name: adapter)
          # rubocop:enable RSpec/VerifiedDoubles
          allow(connection).to receive(:quote) { |value| "'#{value}'" }

          described_class.new(connection)
        end

        it 'casts the JSON columns to text on Postgres' do
          condition = filter_for('PostgreSQL').condition('lyon')

          expect(condition).to include("LOWER(REPLACE(previous_values::text, '[redacted]', '')) LIKE '%lyon%'")
          expect(condition).to include("LOWER(REPLACE(new_values::text, '[redacted]', '')) LIKE '%lyon%'")
        end

        it 'reads the JSON columns as they are stored on SQLite' do
          expect(filter_for('SQLite').condition('lyon')).to include(
            "LOWER(REPLACE(previous_values, '[redacted]', '')) LIKE '%lyon%'"
          )
        end

        it 'casts the JSON columns to CHAR on MySQL' do
          expect(filter_for('Mysql2').condition('lyon')).to include(
            "LOWER(REPLACE(CAST(previous_values AS CHAR), '[redacted]', '')) LIKE '%lyon%'"
          )
        end

        it 'searches the action name and the actor, on every adapter' do
          adapters.each do |adapter|
            condition = filter_for(adapter).condition('ada')

            searched_columns.each do |column|
              expect(condition).to include("LOWER(#{column}) LIKE '%ada%'")
            end
          end
        end

        # Machine identifiers nobody searches for.
        it 'never searches an identifier column' do
          condition = filter_for('PostgreSQL').condition('x')

          %w[operation correlation_key record_id collection status timestamp].each do |column|
            expect(condition).not_to include(column)
          end
        end

        # `!` and not a backslash: MySQL treats a backslash as an escape inside string literals too.
        it 'escapes LIKE wildcards in the term rather than letting them match anything' do
          condition = filter_for('SQLite').condition('50%_off')

          expect(condition).to include("LIKE '%50!%!_off%' ESCAPE '!'")
        end

        it 'escapes the escape character itself' do
          expect(filter_for('SQLite').condition('a!b')).to include("LIKE '%a!!b%'")
        end

        it 'lowercases the term, since the comparison lowercases the column' do
          expect(filter_for('SQLite').condition('LyOn')).to include("LIKE '%lyon%'")
        end

        it 'refuses an adapter it has no text cast for' do
          expect { filter_for('Informix').condition('x') }.to raise_error(
            ForestAdminDatasourceToolkit::Exceptions::ForestException, /not supported on informix/
          )
        end
      end
    end
  end
end
