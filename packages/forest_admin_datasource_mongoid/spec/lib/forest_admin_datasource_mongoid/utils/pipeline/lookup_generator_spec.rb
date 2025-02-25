require 'spec_helper'

module ForestAdminDatasourceMongoid
  module Utils
    module Pipeline
      include ForestAdminDatasourceToolkit::Components::Query
      describe LookupGenerator do
        let(:stack) { [{ prefix: nil, as_fields: [], as_models: [] }] }

        describe 'with the root collection' do
          it 'crashes when non-existent relations are asked for' do
            projection = Projection.new(['myAuthor:firstname'])
            expect do
              described_class.lookup(Post, stack, projection, {})
            end.to raise_error(ForestAdminDatasourceToolkit::Exceptions::ForestException, "🌳🌳🌳 Unexpected relation: 'myAuthor'")
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

          # TODO: when relations are totally implemented
          # it 'should load the post (relation)' do
          #   projection = Projection.new(['post__many_to_one:title'])
          #   pipeline = LookupGenerator.lookup(Comment, stack, projection, {})
          #
          #   expect(pipeline).to eq([
          #                            {
          #                              '$lookup' => {
          #                                'from' => 'posts',
          #                                'localField' => 'post_id',
          #                                'foreignField' => '_id',
          #                                'as' => 'post__manyToOne'
          #                              }
          #                            },
          #                            {
          #                              '$unwind' => {
          #                                'path' => '$post__manyToOne',
          #                                'preserveNullAndEmptyArrays' => true
          #                              }
          #                            }
          #                          ])
          # end
        end
      end
    end
  end
end
