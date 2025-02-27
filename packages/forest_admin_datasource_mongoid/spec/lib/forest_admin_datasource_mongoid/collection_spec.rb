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

    # it 'add all fields of model to the collection' do
    #   expect(collection_post.schema[:fields].keys).to include('_id',
    #                                                           'created_at',
    #                                                           'updated_at',
    #                                                           'title',
    #                                                           'body',
    #                                                           'tag_ids',
    #                                                           'comments',
    #                                                           'author',
    #                                                           'tags')
    # end
    #
    # describe 'fetch_associations' do
    #   it 'add all relation of model to the collection' do
    #     expect(collection_post.schema[:fields].keys).to include('comments', 'author', 'tags')
    #   end
    #
    #   it 'defines the correct association types' do
    #     expect(collection_post.schema[:fields]['comments']).to be_a(ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema)
    #     expect(collection_post.schema[:fields]['author']).to be_a(ForestAdminDatasourceToolkit::Schema::Relations::OneToOneSchema)
    #     expect(collection_post.schema[:fields]['tags']).to be_a(ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema)
    #     expect(collection_user.schema[:fields]['item']).to be_a(ForestAdminDatasourceToolkit::Schema::Relations::PolymorphicManyToOneSchema)
    #     expect(collection_departure.schema[:fields]['user']).to be_a(ForestAdminDatasourceToolkit::Schema::Relations::PolymorphicOneToOneSchema)
    #     expect(collection_comment.schema[:fields]['post']).to be_a(ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema)
    #   end
    #
    #   context 'when the relation is embedded' do
    #     it 'add a single field for an embedded many relation' do
    #       expect(collection_user.schema[:fields]['addresses']).to be_a(ForestAdminDatasourceToolkit::Schema::ColumnSchema)
    #     end
    #
    #     it 'add single field with a composite type' do
    #       expect(collection_band.schema[:fields].keys).to include('label')
    #       expect(collection_band.schema[:fields]['label'].column_type).to eq(
    #         {
    #           '_id' => 'String',
    #           'name' => 'String',
    #           'section' => { '_id' => 'String', 'content' => 'String', 'body' => 'String' }
    #         }
    #       )
    #     end
    #   end
    # end
    #
    # it 'serializes the schema to JSON' do
    #   json_schema = collection_post.schema.to_json
    #   expect { JSON.parse(json_schema) }.not_to raise_error
    #   expect(JSON.parse(json_schema)['fields'].keys).to include('title', 'body', 'comments')
    # end
    #
    # describe '#list' do
    #   it 'returns a serialized list of records' do
    #     post = Post.new(title: 'Test', body: 'Body')
    #     query_result = [post]
    #     query = instance_double(Utils::Query, get: query_result)
    #     allow(Utils::Query).to receive_messages(new: query)
    #
    #     result = collection_post.list(nil, Filter.new, Projection.new(%w[_id title body]))
    #
    #     expect(result).to eq([{ '_id' => post._id, 'title' => post.title, 'body' => post.body }])
    #   end
    #
    #   it 'returns a serialized list of records with many to one relation' do
    #     post = Post.new(title: 'Test', body: 'Body')
    #     comment = Comment.new(name: 'foo', message: 'lorem ipsum', post: post)
    #     query_result = [comment]
    #     query = instance_double(Utils::Query, get: query_result)
    #     allow(Utils::Query).to receive_messages(new: query)
    #
    #     result = collection_comment.list(nil, Filter.new, Projection.new(%w[_id name message post:title]))
    #
    #     expect(result).to eq(
    #       [
    #         {
    #           '_id' => comment._id,
    #           'message' => comment.message,
    #           'name' => comment.name,
    #           'post' => { 'title' => post.title }
    #         }
    #       ]
    #     )
    #   end
    # end
    #
    # describe '#aggregate' do
    #   it 'call QueryAggregate and return an aggregate result' do
    #     Post.new(title: 'Test', body: 'Body')
    #     query = instance_double(Utils::QueryAggregate, get: [{ 'value' => 1 }])
    #     allow(Utils::QueryAggregate).to receive_messages(new: query)
    #
    #     filter = Filter.new
    #     aggregation = Aggregation.new(operation: 'Count')
    #     result = collection_post.aggregate(nil, filter, aggregation, 10)
    #
    #     expect(Utils::QueryAggregate).to(
    #       have_received(:new) do |collection, aggregation_request, filter_request, limit|
    #         expect(collection).to eq(collection_post)
    #         expect(filter).to eq(filter_request)
    #         expect(aggregation).to eq(aggregation_request)
    #         expect(limit).to eq(10)
    #       end
    #     )
    #     expect(result).to eq([{ 'value' => 1 }])
    #   end
    # end
    #
    # describe '#create' do
    #   it 'call create method of model and return object with full projection' do
    #     post = Post.new(title: 'Test', body: 'Body')
    #     model = class_double(Post, create: post)
    #     allow(collection_post).to receive(:model).and_return(model)
    #
    #     result = collection_post.create(nil, { title: 'Test', body: 'Body' })
    #
    #     expect(result).to eq({ '_id' => post._id, 'title' => post.title, 'body' => post.body, 'author' => nil })
    #   end
    # end
    #
    # describe '#update' do
    #   it 'call update method of object' do
    #     model = instance_double(Post, update: true)
    #     query = instance_double(Utils::Query, build: [model])
    #     allow(Utils::Query).to receive_messages(new: query)
    #
    #     collection_post.update(nil, Filter.new, { title: 'new title' })
    #     expect(model).to have_received(:update) do |data|
    #       expect(data).to eq({ title: 'new title' })
    #     end
    #   end
    # end
    #
    # describe '#delete' do
    #   it 'call destroy method of object' do
    #     model = instance_double(Post, destroy: true)
    #     query = instance_double(Utils::Query, build: [model])
    #     allow(Utils::Query).to receive_messages(new: query)
    #
    #     collection_post.delete(nil, Filter.new)
    #     expect(model).to have_received(:destroy)
    #   end
    # end
  end
end
