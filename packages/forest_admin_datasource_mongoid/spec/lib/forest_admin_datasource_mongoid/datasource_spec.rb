require 'spec_helper'

module ForestAdminDatasourceMongoid
  include ForestAdminAgent::Http::Exceptions
  describe Datasource do
    let(:datasource) { described_class.new }

    before do
      logger = instance_double(Logger, log: nil)
      allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(logger)
    end

    it 'adds collections to the datasource' do
      expected = %w[Band Author Tag Comment Departure Post User Team User_addresses CoAuthor]

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
        .to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException, 'Collection Post already defined in datasource')
    end

    describe 'with simple schema' do
      it 'give one collection by default' do
        class_book = Class.new { include Mongoid::Document }
        stub_const('Dummy::Book', class_book)

        allow(ObjectSpace).to receive(:each_object).and_return([Dummy::Book])
        datasource = described_class.new

        expect(datasource.collections.keys).to eq(['Dummy__Book'])
      end

      it 'accept both dots and colons as separator in options' do
        class_book = Class.new do
          include Mongoid::Document
          embeds_one :author, class_name: 'Dummy::Author'
        end
        class_author = Class.new do
          include Mongoid::Document
          field :first_name, type: String
          field :last_name, type: String
        end
        stub_const('Dummy::Book', class_book)
        stub_const('Dummy::Author', class_author)

        allow(ObjectSpace).to receive(:each_object).and_return([Dummy::Book, Dummy::Author])
        datasource = described_class.new(
          options: { flatten_mode: 'manual', flatten_options: { 'Dummy::Book' => { as_models: %w[author.first_name author:last_name] } } }
        )

        expect(datasource.collections.keys).to eq(%w[Dummy__Book Dummy__Book_author_first_name Dummy__Book_author_last_name Dummy__Author])
      end
    end

    describe 'with schema that contains references to unknown model' do
      it 'raise an error' do
        class_book = Class.new do
          include Mongoid::Document
          embeds_one :author
        end
        stub_const('Dummy::Book', class_book)
        allow(ObjectSpace).to receive(:each_object).and_return([Dummy::Book])

        expect { described_class.new }.to raise_error(ForestAdminAgent::Http::Exceptions::NotFoundError, "Collection 'Author' not found.")
      end
    end
  end
end
