require 'spec_helper'

module ForestAdminDatasourceMongoid
  describe Collection do
    let(:datasource) { ForestAdminDatasourceMongoid::Datasource.new }
    let(:collection_post) { described_class.new(datasource, Post) }
    let(:collection_user) { described_class.new(datasource, User) }
    let(:collection_departure) { described_class.new(datasource, Departure) }
    let(:collection_comment) { described_class.new(datasource, Comment) }
    let(:collection_band) { described_class.new(datasource, Band) }

    it 'initializes with the correct model name' do
      expect(collection_post.name).to eq('Post')
    end

    it 'add all fields of model to the collection' do
      expect(collection_post.schema[:fields].keys).to include('_id',
                                                              'created_at',
                                                              'updated_at',
                                                              'title',
                                                              'body',
                                                              'tag_ids',
                                                              'comments',
                                                              'author',
                                                              'tags')
    end

    describe 'fetch_associations' do
      it 'add all relation of model to the collection' do
        expect(collection_post.schema[:fields].keys).to include('comments', 'author', 'tags')
      end

      it 'defines the correct association types' do
        expect(collection_post.schema[:fields]['comments']).to be_a(ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema)
        expect(collection_post.schema[:fields]['author']).to be_a(ForestAdminDatasourceToolkit::Schema::Relations::OneToOneSchema)
        expect(collection_post.schema[:fields]['tags']).to be_a(ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema)
        expect(collection_user.schema[:fields]['item']).to be_a(ForestAdminDatasourceToolkit::Schema::Relations::PolymorphicManyToOneSchema)
        expect(collection_departure.schema[:fields]['user']).to be_a(ForestAdminDatasourceToolkit::Schema::Relations::PolymorphicOneToOneSchema)
        expect(collection_comment.schema[:fields]['post']).to be_a(ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema)
      end

      context 'when the relation is embedded' do
        it 'add a single field for an embedded many relation' do
          expect(collection_user.schema[:fields]['addresses']).to be_a(ForestAdminDatasourceToolkit::Schema::ColumnSchema)
        end

        it 'add single field with a composite type' do
          expect(collection_band.schema[:fields].keys).to include('label')
          expect(collection_band.schema[:fields]['label'].column_type).to eq(
            {
              '_id' => 'String',
              'name' => 'String',
              'section' => { '_id' => 'String', 'content' => 'String', 'body' => 'String' }
            }
          )
        end
      end
    end

    it 'serializes the schema to JSON' do
      json_schema = collection_post.schema.to_json
      expect { JSON.parse(json_schema) }.not_to raise_error
      expect(JSON.parse(json_schema)['fields'].keys).to include('title', 'body', 'comments')
    end

    # TODO: works but waiting crud is fully implemented
    # describe '#list' do
    #   it 'returns a serialized list of records' do
    #     allow(Utils::Query).to receive_message_chain(:new, :get).and_return([Post.new(title: 'Test', body: 'Body')])
    #     allow(Utils::MongoidSerializer).to receive(:new).and_return(double(to_hash: { title: 'Test', body: 'Body' }))
    #
    #     result = collection_post.list(nil, {}, nil)
    #
    #     expect(result).to eq([{ title: 'Test', body: 'Body' }])
    #   end
    # end
  end
end
