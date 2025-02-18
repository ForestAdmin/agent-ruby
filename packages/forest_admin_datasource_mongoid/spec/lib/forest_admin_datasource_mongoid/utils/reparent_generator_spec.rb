require 'spec_helper'
require 'mongoid'

module ForestAdminDatasourceMongoid
  module Utils
    module Pipeline
      include ForestAdminDatasourceToolkit::Components::Query
      describe ReparentGenerator do
        let(:author_model) do
          Class.new do
            include Mongoid::Document

            field :firstname
            field :lastname
          end
        end

        let(:edition_model) do
          Class.new do
            include Mongoid::Document

            field :isbn
            field :year
          end
        end

        let(:model) do
          Class.new do
            include Mongoid::Document

            field :title, type: String
            field :publishers, type: Array
            embeds_one :author, class_name: 'Dummy::Author'
            embeds_many :editions, class_name: 'Dummy::Edition'

            field :moreThen30Fields, type: Hash, default: {}
          end
        end

        before do
          stub_const('Dummy::Author', author_model)
          stub_const('Dummy::Edition', edition_model)
          stub_const('Dummy::Book', model)
        end

        after do
          Mongoid.purge!
        end

        context 'when generating pipelines' do
          it 'generates an empty pipeline for the null prefix' do
            stack = [{ prefix: nil, as_fields: [], as_models: [] }]
            pipeline = described_class.reparent(Dummy::Book, stack)
            expect(pipeline).to eq([])
          end

          it 'generates a single $replaceRoot to unnest an object' do
            pipeline = described_class.reparent(Dummy::Book, [
                                                  { prefix: nil, as_fields: [], as_models: ['author'] },
                                                  { prefix: 'author', as_fields: [], as_models: [] }
                                                ])

            expect(pipeline).to eq([
                                     {
                                       '$replaceRoot' => {
                                         'newRoot' => {
                                           '$mergeObjects' => [
                                             '$author',
                                             ConditionGenerator.tag_record_if_not_exist('author', {
                                                                                          '_id' => { '$concat' => [{ '$toString' => '$_id' }, '.author'] },
                                                                                          'parent_id' => '$_id',
                                                                                          'parent' => '$$ROOT'
                                                                                        })
                                           ]
                                         }
                                       }
                                     }
                                   ])
          end

          it 'generates an $unwind and $replaceRoot to unnest an array of objects' do
            pipeline = described_class.reparent(Dummy::Book, [
                                                  { prefix: nil, as_fields: [], as_models: ['editions'] },
                                                  { prefix: 'editions', as_fields: [], as_models: [] }
                                                ])

            expect(pipeline).to eq([
                                     { '$unwind' => { 'includeArrayIndex' => 'index', 'path' => '$editions' } },
                                     {
                                       '$replaceRoot' => {
                                         'newRoot' => {
                                           '$mergeObjects' => [
                                             '$editions',
                                             ConditionGenerator.tag_record_if_not_exist('editions', {
                                                                                          '_id' => { '$concat' => [{ '$toString' => '$_id' }, '.editions.', { '$toString' => '$index' }] },
                                                                                          'parent_id' => '$_id',
                                                                                          'parent' => '$$ROOT'
                                                                                        })
                                           ]
                                         }
                                       }
                                     }
                                   ])
          end

          it 'generates a $replaceRoot to unnest a field' do
            pipeline = described_class.reparent(Dummy::Book, [
                                                  { prefix: nil, as_fields: [], as_models: ['title'] },
                                                  { prefix: 'title', as_fields: [], as_models: [] }
                                                ])

            expect(pipeline).to eq([
                                     {
                                       '$replaceRoot' => {
                                         'newRoot' => {
                                           '$mergeObjects' => [
                                             { 'content' => '$title' },
                                             ConditionGenerator.tag_record_if_not_exist('title', {
                                                                                          '_id' => { '$concat' => [{ '$toString' => '$_id' }, '.title'] },
                                                                                          'parent_id' => '$_id',
                                                                                          'parent' => '$$ROOT'
                                                                                        })
                                           ]
                                         }
                                       }
                                     }
                                   ])
          end

          it 'generates an $unwind and $replaceRoot to unnest an array of primitives' do
            pipeline = described_class.reparent(Dummy::Book, [
                                                  { prefix: nil, as_fields: [], as_models: ['publishers'] },
                                                  { prefix: 'publishers', as_fields: [], as_models: [] }
                                                ])

            expect(pipeline).to eq([
                                     { '$unwind' => { 'includeArrayIndex' => 'index', 'path' => '$publishers' } },
                                     {
                                       '$replaceRoot' => {
                                         'newRoot' => {
                                           '$mergeObjects' => [
                                             { 'content' => '$publishers' },
                                             ConditionGenerator.tag_record_if_not_exist('publishers', {
                                                                                          '_id' => { '$concat' => [{ '$toString' => '$_id' }, '.publishers.', { '$toString' => '$index' }] },
                                                                                          'parent_id' => '$_id',
                                                                                          'parent' => '$$ROOT'
                                                                                        })
                                           ]
                                         }
                                       }
                                     }
                                   ])
          end

          context 'when flattening objects with more than 30 fields' do
            it 'splits $addFields operations every 30 fields (DocumentDB limitation)' do
              simulated_fields = (1..32).map { |i| "moreThen30Fields.field#{i}" }

              pipeline = described_class.reparent(Dummy::Book, [
                                                    { prefix: nil, as_fields: simulated_fields, as_models: [] }
                                                  ])

              add_fields_operations = pipeline.select { |operation| operation.key?('$addFields') }
              total_fields = add_fields_operations.sum { |op| op['$addFields'].keys.length }

              expect(add_fields_operations.length).to eq(2)
              expect(total_fields).to eq(32)
            end
          end
        end
      end
    end
  end
end
