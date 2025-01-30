require 'spec_helper'

module ForestAdminDatasourceMongoid
  module Utils
    include ForestAdminDatasourceToolkit::Components::Query
    describe MongoidSerializer do
      describe '#to_hash' do
        describe 'without relations' do
          let(:post) { Post.new(title: 'foo', body: 'fake content') }

          it 'return a mongoid object serialized with full projection' do
            expect(described_class.new(post).to_hash(Projection.new(%w[title body]))).to eq(
              { 'title' => 'foo', 'body' => 'fake content' }
            )
          end

          it 'return a mongoid object serialized with partial projection' do
            expect(described_class.new(post).to_hash(Projection.new(%w[title]))).to eq(
              { 'title' => 'foo' }
            )
          end
        end

        describe 'with relations' do
          let(:post) { Post.first }
          let(:author) { Author.first }

          before do
            Author.create!(
              first_name: 'john',
              last_name: 'doe',
              post: Post.create!(title: 'foo', body: 'fake content')
            )
          end

          it 'return a mongoid object serialized based on projection with ManyToOne relation' do
            projection = Projection.new(%w[first_name last_name post:title post:body])

            expect(described_class.new(author).to_hash(projection)).to eq(
              {
                'first_name' => 'john',
                'last_name' => 'doe',
                'post' => { 'title' => 'foo', 'body' => 'fake content' }
              }
            )
          end

          it 'return a mongoid object serialized based on projection with OneToOne relation' do
            projection = Projection.new(%w[title body author:first_name author:lastname])

            expect(described_class.new(post).to_hash(projection)).to eq(
              {
                'title' => 'foo',
                'body' => 'fake content',
                'author' => { 'first_name' => 'john' }
              }
            )
          end
        end
      end
    end
  end
end
