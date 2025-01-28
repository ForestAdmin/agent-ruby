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
          let(:post) { Post.create!(title: 'foo', body: 'fake content') }

          it 'return a mongoid object serialized with full projection' do
            expect(described_class.new(post).to_hash(Projection.new(%w[title body]))).to eq(
              { 'title' => 'foo', 'body' => 'fake content' }
            )
          end

          # it 'return a mongoid object serialized with partial projection' do
          #   post = Post.new(title: 'foo', body: 'fake content')
          #   expect(described_class.new(post).to_hash(Projection.new(%w[title]))).to eq(
          #     { 'title' => 'foo' }
          #   )
          # end
        end
      end
    end
  end
end
