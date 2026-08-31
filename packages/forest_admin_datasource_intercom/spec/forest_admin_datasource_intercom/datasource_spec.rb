module ForestAdminDatasourceIntercom
  RSpec.describe Datasource do
    subject(:datasource) { described_class.new }

    it 'boots without reaching Intercom' do
      expect { datasource }.not_to raise_error
    end

    it 'registers no collection yet' do
      expect(datasource.collections).to be_empty
    end

    it 'names the collections it holds when printed' do
      expect(datasource.inspect).to eq('#<ForestAdminDatasourceIntercom::Datasource collections=[]>')
    end
  end
end
