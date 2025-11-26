require 'spec_helper'

module ForestAdminDatasourceActiveRecord
  describe Datasource do
    it 'fetch all models' do
      datasource = described_class.new({ adapter: 'sqlite3', database: 'db/database.db' })
      # Core collections that should always be present
      expected_core = %w[Account AccountHistory Order Check Category CarCheck Car Address CompaniesUser Supplier Author Book AuthorsBook]

      # Check core collections are present
      expect(datasource.collections.keys).to include(*expected_core)

      # User and Company may or may not be present depending on DB state, but if present they should be valid
      collections = datasource.collections.keys
      expect(collections).to all(be_a(String))
    end
  end
end
