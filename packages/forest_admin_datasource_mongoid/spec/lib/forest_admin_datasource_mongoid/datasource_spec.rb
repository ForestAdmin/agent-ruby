require 'spec_helper'

module ForestAdminDatasourceMongoid
  include ForestAdminDatasourceToolkit::Exceptions
  describe Datasource do
    let(:datasource) { described_class.new }

    before do
      logger = instance_double(Logger, log: nil)
      allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(logger)
    end

    it 'adds collections to the datasource' do
      expected = %w[Band Author Tag Comment Departure Post User Team addresses_User CoAuthor Dummy__MyModel]

      expect(datasource.collections.keys).to match_array(expected)
    end

    it 'only loads models that are Mongoid::Document classes' do
      expect(datasource.collections.keys).not_to include('NotMongoidModel')
    end

    it 'does not load embedded models as collections' do
      expect(datasource.collections.keys).not_to include('Address')
    end

    it 'does not load any models if no Mongoid::Document classes are present' do
      # Simulates the absence of Mongoid models in the application by forcing the each_object method
      # to return an empty list. This allows testing the behavior of the Datasource when no Mongoid models are available.
      allow(ObjectSpace).to receive(:each_object).and_return([])

      datasource = described_class.new
      expect(datasource.collections.keys).to be_empty
    end

    it 'raises an exception if trying to add a collection with an existing name' do
      logger = instance_double(Logger, log: nil)
      allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(logger)
      expect { datasource.add_collection(Collection.new(datasource, Post, [{ prefix: nil, as_fields: [], as_models: [] }])) }
        .to raise_error(ForestException, '🌳🌳🌳 Collection Post already defined in datasource')
    end
  end
end
