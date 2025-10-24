require 'spec_helper'

module ForestAdminDatasourceMongoid
  module Utils
    module Pipeline
      describe VirtualFieldGenerator do
        it 'does not add fields that are not within the projection' do
          projection = []
          stack = [{ prefix: nil, as_fields: [], as_models: ['author'] }]
          pipeline = described_class.add_virtual(Post, stack, projection)

          expect(pipeline).to eq([])
        end

        it 'adds virtual fields fake many to one' do
          projection = ['author:_id', 'author:parent_id']
          stack = [{ prefix: nil, as_fields: [], as_models: ['author'] }]
          pipeline = described_class.add_virtual(Post, stack, projection)

          expect(pipeline).to eq([
                                   {
                                     '$addFields' => {
                                       'author._id' => ConditionGenerator.tag_record_if_not_exist_by_value('author', {
                                                                                                             '$concat' => [{ '$toString' => '$_id' }, '.author']
                                                                                                           }),
                                       'author.parent_id' => ConditionGenerator.tag_record_if_not_exist_by_value('author', '$_id')
                                     }
                                   }
                                 ])
        end

        it 'adds virtual fields on boxed many to one' do
          projection = ['title:_id', 'title:parent_id', 'title:content']
          stack = [{ prefix: nil, as_fields: [], as_models: ['title'] }]
          pipeline = described_class.add_virtual(Post, stack, projection)

          expect(pipeline).to eq([
                                   {
                                     '$addFields' => {
                                       'title._id' => ConditionGenerator.tag_record_if_not_exist_by_value('title', {
                                                                                                            '$concat' => [{ '$toString' => '$_id' }, '.title']
                                                                                                          }),
                                       'title.parent_id' => ConditionGenerator.tag_record_if_not_exist_by_value('title', '$_id'),
                                       'title.content' => '$title'
                                     }
                                   }
                                 ])
        end

        it 'adds nested dependencies besides for parent_id (for server-side queries only)' do
          projection = ['author:country:_id']
          stack = [{ prefix: nil, as_fields: [], as_models: ['author'] }]
          pipeline = described_class.add_virtual(Post, stack, projection)

          expect(pipeline).to eq([
                                   {
                                     '$addFields' => {
                                       'author.country._id' => ConditionGenerator.tag_record_if_not_exist_by_value(
                                         'author.country',
                                         {
                                           '$concat' => [{ '$toString' => '$_id' }, '.author.country']
                                         }
                                       )
                                     }
                                   }
                                 ])
        end

        it 'adds nested dependencies' do
          projection = ['author:country:name']
          stack = [{ prefix: nil, as_fields: [], as_models: ['author'] }]
          pipeline = described_class.add_virtual(Post, stack, projection)

          expect(pipeline).to eq([
                                   {
                                     '$addFields' => {
                                       'author.country.name' => ConditionGenerator.tag_record_if_not_exist_by_value(
                                         'author.country',
                                         '$author.country.name'
                                       )
                                     }
                                   }
                                 ])
        end

        it 'crashes on nested parent_id (for server-side queries only)' do
          projection = ['author:country:parent_id']
          stack = [{ prefix: nil, as_fields: [], as_models: ['author'] }]
          expect do
            described_class.add_virtual(Post, stack, projection)
          end.to raise_error(ForestAdminDatasourceToolkit::Exceptions::UnprocessableError, 'Fetching virtual parent_id deeper than 1 level is not supported.')
        end
      end
    end
  end
end
