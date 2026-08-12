require 'spec_helper'

module ForestAdminAgent
  module AuditTrail
    module Sql
      # The store specs cover the SQLite path end to end; these pin the Postgres-only behaviour (schema
      # creation and the advisory lock) without needing a Postgres server.
      describe Migrator do
        subject(:migrator) { described_class.new(connection, schema: 'forest', table_name: 'audit_logs') }

        let(:executed) { [] }
        # A plain double on purpose: this fakes the Postgres adapter, which cannot be loaded here (no `pg`
        # gem), and `quote_schema_name` only exists on it.
        let(:connection) do
          double(
            'PostgreSQL connection',
            adapter_name: 'PostgreSQL',
            create_table: nil,
            add_index: nil,
            add_column: nil,
            select_values: ['forest.audit_logs:001-create-audit-logs',
                            'forest.audit_logs:002-index-record-and-correlation'],
            quote_schema_name: '"forest"',
            quote_table_name: '"forest.audit_migrations"',
            quote: "'x'"
          )
        end

        before do
          allow(connection).to receive(:execute) { |sql| executed << sql }
          allow(connection).to receive(:transaction).and_yield
        end

        it 'creates the schema before taking the lock, so the migrations can see it' do
          migrator.run

          expect(executed.first).to eq('CREATE SCHEMA IF NOT EXISTS "forest"')
        end

        it 'runs the migrations under a transaction-scoped advisory lock' do
          migrator.run

          expect(connection).to have_received(:transaction)
          expect(executed).to include('SELECT pg_advisory_xact_lock(17999, 21076)')
        end

        def raise_on_create_schema(message)
          allow(connection).to receive(:execute) do |sql|
            raise ActiveRecord::StatementInvalid, message if sql.include?('CREATE SCHEMA')

            executed << sql
          end
        end

        it 'tolerates another instance having created the schema concurrently' do
          raise_on_create_schema('ERROR: schema "forest" already exists')

          expect { migrator.run }.not_to raise_error
          expect(executed).to include('SELECT pg_advisory_xact_lock(17999, 21076)')
        end

        it 'still reports a schema creation that failed for another reason' do
          raise_on_create_schema('ERROR: permission denied for database')

          expect { migrator.run }.to raise_error(ActiveRecord::StatementInvalid, /permission denied/)
        end

        it 'skips migrations already applied to this table' do
          migrator.run

          expect(connection).not_to have_received(:create_table).with('forest.audit_logs', any_args)
        end
      end
    end
  end
end
