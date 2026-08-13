require 'spec_helper'

module ForestAdminAgent
  module AuditTrail
    module Sql
      # The store specs run on SQLite, so the SQL for the other adapters is pinned here — a fake connection
      # is enough, the class only builds a condition string.
      describe FieldFilter do
        def filter_for(adapter)
          # rubocop:disable RSpec/VerifiedDoubles
          connection = double(adapter.to_s, adapter_name: adapter)
          # rubocop:enable RSpec/VerifiedDoubles
          allow(connection).to receive(:quote) { |value| "'#{value}'" }

          described_class.new(connection)
        end

        it 'asks Postgres for the JSON keys of both sides' do
          condition = filter_for('PostgreSQL').condition(%w[status note])

          expect(condition).to eq(
            'EXISTS (SELECT 1 FROM jsonb_object_keys(previous_values::jsonb) AS key ' \
            "WHERE key IN ('status', 'note')) OR " \
            "EXISTS (SELECT 1 FROM jsonb_object_keys(new_values::jsonb) AS key WHERE key IN ('status', 'note'))"
          )
        end

        # `?|` would read as a bind placeholder, and `json_extract` cannot tell a key holding null from a
        # missing one.
        it 'never emits a bind placeholder or json_extract' do
          %w[PostgreSQL SQLite Mysql2].each do |adapter|
            condition = filter_for(adapter).condition(%w[status])

            expect(condition).not_to include('?')
            expect(condition).not_to include('json_extract')
          end
        end

        it 'asks SQLite for the type at a quoted path on both sides' do
          condition = filter_for('SQLite').condition(%w[status])

          expect(condition).to eq(
            %(json_type(previous_values, '$."status"') IS NOT NULL OR ) +
            %(json_type(new_values, '$."status"') IS NOT NULL)
          )
        end

        it 'asks MySQL for any of the paths on both sides' do
          condition = filter_for('Mysql2').condition(%w[status note])

          expect(condition).to eq(
            %(JSON_CONTAINS_PATH(previous_values, 'one', '$."status"', '$."note"') OR ) +
            %(JSON_CONTAINS_PATH(new_values, 'one', '$."status"', '$."note"'))
          )
        end

        it 'treats MariaDB like MySQL' do
          expect(filter_for('Mariadb').condition(%w[status])).to include('JSON_CONTAINS_PATH')
        end

        # A dot in a field name is part of the name, not a traversal into the object.
        it 'quotes a field name holding a dot as a single key' do
          expect(filter_for('SQLite').condition(['address.city'])).to include(%('$."address.city"'))
          expect(filter_for('Mysql2').condition(['address.city'])).to include(%('$."address.city"'))
        end

        it 'escapes a quote inside a field name' do
          expect(filter_for('SQLite').condition(['we"ird'])).to include(%q($."we\"ird"))
        end

        it 'refuses an adapter it has no JSON test for' do
          expect { filter_for('Informix').condition(%w[status]) }.to raise_error(
            ForestAdminDatasourceToolkit::Exceptions::ForestException, /not supported on informix/
          )
        end
      end
    end
  end
end
