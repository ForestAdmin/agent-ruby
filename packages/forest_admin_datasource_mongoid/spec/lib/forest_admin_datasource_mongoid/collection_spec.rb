require 'spec_helper'

module ForestAdminDatasourceMongoid
  include ForestAdminDatasourceToolkit::Components::Query
  describe Collection do
    before do
      logger = instance_double(Logger, log: nil)
      allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(logger)
    end

    let(:datasource) { ForestAdminDatasourceMongoid::Datasource.new(options: { flatten_mode: 'auto' }) }
    let(:collection_post) { described_class.new(datasource, Post, [{ prefix: nil, as_fields: [], as_models: [] }]) }
    let(:collection_user) { described_class.new(datasource, User, [{ prefix: nil, as_fields: [], as_models: [] }]) }
    let(:collection_departure) { described_class.new(datasource, Departure, [{ prefix: nil, as_fields: [], as_models: [] }]) }
    let(:collection_comment) { described_class.new(datasource, Comment, [{ prefix: nil, as_fields: [], as_models: [] }]) }
    let(:collection_band) { described_class.new(datasource, Band, [{ prefix: nil, as_fields: [], as_models: [] }]) }

    it 'initializes with the correct model name' do
      expect(collection_post.name).to eq('Post')
    end

    it 'builds a collection with the right datasource and schema' do
      expect(collection_post.datasource).to eq(datasource)
      schema = collection_post.schema

      expect(schema[:actions]).to eq({})
      expect(schema[:charts]).to eq([])
      expect(schema[:countable]).to be(true)
      expect(schema[:searchable]).to be(false)
      expect(schema[:segments]).to eq([])
      expect(schema[:fields].keys).to include(
        '_id',
        'created_at',
        'updated_at',
        'title',
        'body',
        'rating',
        'tag_ids',
        'user_id',
        'user_id__many_to_one',
        'co_author'
      )
    end

    it 'escapes collection names' do
      model = Class.new do
        include Mongoid::Document
        field :content, type: String
      end

      stub_const('Dummy::MyModel', model)

      collection = described_class.new(datasource, Dummy::MyModel, [{ prefix: nil, as_fields: [], as_models: [] }])

      expect(collection.name).to eq('Dummy__MyModel')
    end
  end
end
