require 'spec_helper'

module ForestAdminDatasourceMongoid
  module Utils
    module Pipeline
      include ForestAdminDatasourceToolkit::Components::Query
      describe LookupGenerator do
        describe 'with the root collection' do
          let(:stack) { [{ prefix: nil, as_fields: [], as_models: [] }] }

          it 'crashes when non-existent relations are asked for' do
            projection = Projection.new(['myAuthor:firstname'])
            expect do
              described_class.lookup(Post, stack, projection, {})
            end.to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException, "Unexpected relation: 'myAuthor'")
          end

          it 'does nothing with projection that only contains columns' do
            projection = Projection.new(['title'])
            pipeline = described_class.lookup(Post, stack, projection, {})

            expect(pipeline).to eq([])
          end

          it 'does nothing with projection that only contains fake relations' do
            projection = Projection.new(['label:name'])
            pipeline = described_class.lookup(Band, stack, projection, {})

            expect(pipeline).to eq([])
          end

          it 'loads the post (relation)' do
            projection = Projection.new(['post_id__many_to_one:title'])
            pipeline = described_class.lookup(Comment, stack, projection, {})

            expect(pipeline).to eq(
              [
                {
                  '$lookup' => {
                    'from' => 'Post',
                    'localField' => 'post_id',
                    'foreignField' => '_id',
                    'as' => 'post_id__many_to_one'
                  }
                },
                {
                  '$unwind' => {
                    'path' => '$post_id__many_to_one',
                    'preserveNullAndEmptyArrays' => true
                  }
                }
              ]
            )
          end

          it 'loads the user (relation) with nested fields' do
            projection = Projection.new(['user_id__many_to_one:address@@@city'])
            pipeline = described_class.lookup(Post, stack, projection, {})

            expect(pipeline).to eq(
              [
                {
                  '$lookup' => {
                    'as' => 'user_id__many_to_one',
                    'foreignField' => '_id',
                    'from' => 'User',
                    'localField' => 'user_id'
                  }
                },
                { '$unwind' => { 'path' => '$user_id__many_to_one', 'preserveNullAndEmptyArrays' => true } },
                {
                  '$addFields' => {
                    'user_id__many_to_one.address@@@city' => '$user_id__many_to_one.address.city'
                  }
                }
              ]
            )
          end

          describe 'include' do
            it 'returns the nested field if the parent is included' do
              projection = Projection.new(['user_id__many_to_one:address@@@city'])
              pipeline = described_class.lookup(Post, stack, projection, { include: ['user_id__many_to_one'] })

              expect(pipeline).to eq(
                [
                  {
                    '$lookup' => {
                      'as' => 'user_id__many_to_one',
                      'foreignField' => '_id',
                      'from' => 'User',
                      'localField' => 'user_id'
                    }
                  },
                  { '$unwind' => { 'path' => '$user_id__many_to_one', 'preserveNullAndEmptyArrays' => true } },
                  {
                    '$addFields' => {
                      'user_id__many_to_one.address@@@city' => '$user_id__many_to_one.address.city'
                    }
                  }
                ]
              )
            end

            it 'does not add the nested field if the parent is not included' do
              projection = Projection.new(['user_id__many_to_one:address@@@city'])
              pipeline = described_class.lookup(Post, stack, projection, { include: [] })

              expect(pipeline).to eq([])
            end
          end

          describe 'exclude' do
            it 'does not add the nested field if the parent is excluded' do
              projection = Projection.new(['user_id__many_to_one:address@@@city'])
              pipeline = described_class.lookup(Post, stack, projection, { exclude: ['user_id__many_to_one'] })

              expect(pipeline).to eq([])
            end

            it 'does not add the nested field if the parent is not included' do
              projection = Projection.new(['user_id__many_to_one:address@@@city'])
              pipeline = described_class.lookup(Post, stack, projection, { exclude: [] })

              expect(pipeline).to eq(
                [
                  {
                    '$lookup' => {
                      'as' => 'user_id__many_to_one',
                      'foreignField' => '_id',
                      'from' => 'User',
                      'localField' => 'user_id'
                    }
                  },
                  { '$unwind' => { 'path' => '$user_id__many_to_one', 'preserveNullAndEmptyArrays' => true } },
                  {
                    '$addFields' => {
                      'user_id__many_to_one.address@@@city' => '$user_id__many_to_one.address.city'
                    }
                  }
                ]
              )
            end
          end

          it 'loads the user (relation) with double nested fields' do
            projection = Projection.new(['user_id__many_to_one:address@@@meta@@@length'])
            pipeline = described_class.lookup(Post, stack, projection, {})

            expect(pipeline).to eq(
              [
                {
                  '$lookup' => {
                    'as' => 'user_id__many_to_one',
                    'foreignField' => '_id',
                    'from' => 'User',
                    'localField' => 'user_id'
                  }
                },
                { '$unwind' => { 'path' => '$user_id__many_to_one', 'preserveNullAndEmptyArrays' => true } },
                {
                  '$addFields' => {
                    'user_id__many_to_one.address@@@meta@@@length' => '$user_id__many_to_one.address.meta.length'
                  }
                }
              ]
            )
          end

          it 'loads the post user city (double relation with nested field)' do
            projection = Projection.new(['post_id__many_to_one:user_id__many_to_one:address@@@city'])
            pipeline = described_class.lookup(Author, stack, projection, {})

            expect(pipeline).to eq(
              [
                {
                  '$lookup' => {
                    'as' => 'post_id__many_to_one',
                    'foreignField' => '_id',
                    'from' => 'Post',
                    'localField' => 'post_id'
                  }
                },
                { '$unwind' => { 'path' => '$post_id__many_to_one', 'preserveNullAndEmptyArrays' => true } },
                {
                  '$lookup' => {
                    'as' => 'post_id__many_to_one.user_id__many_to_one',
                    'foreignField' => '_id',
                    'from' => 'User',
                    'localField' => 'post_id__many_to_one.user_id'
                  }
                },
                { '$unwind' => { 'path' => '$post_id__many_to_one.user_id__many_to_one', 'preserveNullAndEmptyArrays' => true } },
                {
                  '$addFields' => {
                    'user_id__many_to_one.address@@@city' => '$user_id__many_to_one.address.city'
                  }
                },
                {
                  '$addFields' => {
                    'post_id__many_to_one.user_id__many_to_one.address@@@city' => '$post_id__many_to_one.user_id__many_to_one.address.city'
                  }
                }
              ]
            )
          end

          it 'loads the post user address meta length (double relation with double nested field)' do
            projection = Projection.new(['post_id__many_to_one:user_id__many_to_one:address@@@meta@@@length'])
            pipeline = described_class.lookup(Author, stack, projection, {})

            expect(pipeline).to eq(
              [
                {
                  '$lookup' => {
                    'as' => 'post_id__many_to_one',
                    'foreignField' => '_id',
                    'from' => 'Post',
                    'localField' => 'post_id'
                  }
                },
                { '$unwind' => { 'path' => '$post_id__many_to_one', 'preserveNullAndEmptyArrays' => true } },
                {
                  '$lookup' => {
                    'as' => 'post_id__many_to_one.user_id__many_to_one',
                    'foreignField' => '_id',
                    'from' => 'User',
                    'localField' => 'post_id__many_to_one.user_id'
                  }
                },
                { '$unwind' => { 'path' => '$post_id__many_to_one.user_id__many_to_one', 'preserveNullAndEmptyArrays' => true } },
                {
                  '$addFields' => {
                    'user_id__many_to_one.address@@@meta@@@length' => '$user_id__many_to_one.address.meta.length'
                  }
                },
                {
                  '$addFields' => {
                    'post_id__many_to_one.user_id__many_to_one.address@@@meta@@@length' => '$post_id__many_to_one.user_id__many_to_one.address.meta.length'
                  }
                }
              ]
            )
          end

          it 'loads the post co_author user (relation within fake relation)' do
            projection = Projection.new(['co_author:user_id__many_to_one:name'])
            pipeline = described_class.lookup(Post, stack, projection, {})

            expect(pipeline).to eq(
              [
                {
                  '$lookup' => {
                    'as' => 'co_author.user_id__many_to_one',
                    'foreignField' => '_id',
                    'from' => 'User',
                    'localField' => 'co_author.user_id'
                  }
                },
                { '$unwind' => { 'path' => '$co_author.user_id__many_to_one', 'preserveNullAndEmptyArrays' => true } }
              ]
            )
          end

          it 'loads the comment post user (nested relation)' do
            projection = Projection.new(['post_id__many_to_one:user_id__many_to_one:name'])
            pipeline = described_class.lookup(Comment, stack, projection, {})

            expect(pipeline).to eq(
              [
                {
                  '$lookup' => {
                    'as' => 'post_id__many_to_one',
                    'foreignField' => '_id',
                    'from' => 'Post',
                    'localField' => 'post_id'
                  }
                },
                { '$unwind' => { 'path' => '$post_id__many_to_one', 'preserveNullAndEmptyArrays' => true } },
                {
                  '$lookup' => {
                    'as' => 'post_id__many_to_one.user_id__many_to_one',
                    'foreignField' => '_id',
                    'from' => 'User',
                    'localField' => 'post_id__many_to_one.user_id'
                  }
                },
                { '$unwind' => { 'path' => '$post_id__many_to_one.user_id__many_to_one', 'preserveNullAndEmptyArrays' => true } }
              ]
            )
          end
        end

        describe 'with a reparented collection' do
          let(:stack) do
            [
              { prefix: nil, as_fields: [], as_models: ['co_author'] },
              { prefix: 'co_author', as_fields: [], as_models: [] }
            ]
          end

          it 'loads the post co_author user (relation)' do
            projection = Projection.new(['user_id__many_to_one:name'])
            pipeline = described_class.lookup(Post, stack, projection, {})

            expect(pipeline).to eq(
              [
                {
                  '$lookup' => {
                    'as' => 'user_id__many_to_one',
                    'foreignField' => '_id',
                    'from' => 'User',
                    'localField' => 'user_id'
                  }
                },
                { '$unwind' => { 'path' => '$user_id__many_to_one', 'preserveNullAndEmptyArrays' => true } }
              ]
            )
          end

          it 'loads the user (relation within fake relation)' do
            projection = Projection.new(['parent:user_id__many_to_one:name'])
            pipeline = described_class.lookup(Post, stack, projection, {})

            expect(pipeline).to eq(
              [
                {
                  '$lookup' => {
                    'as' => 'parent.user_id__many_to_one',
                    'foreignField' => '_id',
                    'from' => 'User',
                    'localField' => 'parent.user_id'
                  }
                },
                { '$unwind' => { 'path' => '$parent.user_id__many_to_one', 'preserveNullAndEmptyArrays' => true } }
              ]
            )
          end
        end
      end
    end
  end
end
