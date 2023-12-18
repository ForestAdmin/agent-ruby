require 'spec_helper'

module ForestAdminDatasourceToolkit
  describe Datasource do
    before do
      @datasource = described_class.new
      @collection = Collection.new(@datasource, '__collection__')
      @datasource.add_collection(@collection)
    end

    it 'expose collections from datasource as an hash' do
      expect(@datasource.collections).to be_a Hash
    end

    it 'return an empty hash for charts' do
      expect(@datasource.charts).to be_a Hash
      expect(@datasource.charts).to eq({})
    end

    it 'get collection from datasource' do
      expect(@datasource.get_collection('__collection__')).to eq(@collection)
    end

    it 'raise an error when collection does not exist' do
      expect do
        @datasource.get_collection('__no_such_collection__')
      end.to raise_error(
        ForestAdminDatasourceToolkit::Exceptions::ForestException,
        '🌳🌳🌳 Collection __no_such_collection__ not found.'
      )
    end

    it 'raise an error when chart does not exist' do
      expect do
        @datasource.render_chart({}, '__no_such_chart__')
      end.to raise_error(
        ForestAdminDatasourceToolkit::Exceptions::ForestException,
        '🌳🌳🌳 No chart named __no_such_chart__ exists on this datasource.'
      )
    end

    it 'raise an error when collection already exist' do
      expect do
        @datasource.add_collection(@collection)
      end.to raise_error(
        ForestAdminDatasourceToolkit::Exceptions::ForestException,
        '🌳🌳🌳 Collection __collection__ already defined in datasource'
      )
    end
  end
end
