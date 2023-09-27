require 'spec_helper'

module ForestAdminDatasourceActiveRecord
  describe Datasource do
    it 'fetch all models' do
      datasource = Datasource.new(adapter: 'sqlite3', database: 'db/database.db')
      expected = %w[InternalMetadata SchemaMigration User Order Check Category CarCheck Car Address]

      expect(datasource.collections.keys).to match_array(expected)
    end
  end
end
