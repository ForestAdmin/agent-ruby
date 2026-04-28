module ForestAdminDatasourceSnowflake
  module Parser
    module Relation
      PK_TABLE_NAME_IDX  = 3
      PK_COLUMN_NAME_IDX = 4
      FK_TABLE_NAME_IDX  = 7
      FK_COLUMN_NAME_IDX = 8

      QUERY = 'SHOW IMPORTED KEYS IN SCHEMA'.freeze

      module_function

      def discover(datasource)
        rows = datasource.with_connection do |conn|
          stmt = conn.prepare(QUERY)
          begin
            stmt.execute
            stmt.fetch_all || []
          ensure
            stmt.drop
          end
        end

        rows.map do |row|
          {
            source_table: row[FK_TABLE_NAME_IDX],
            source_column: row[FK_COLUMN_NAME_IDX],
            target_table: row[PK_TABLE_NAME_IDX],
            target_column: row[PK_COLUMN_NAME_IDX]
          }
        end
      end
    end
  end
end
