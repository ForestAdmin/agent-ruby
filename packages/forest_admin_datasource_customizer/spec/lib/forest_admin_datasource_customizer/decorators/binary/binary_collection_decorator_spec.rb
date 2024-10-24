require 'spec_helper'
require 'shared/caller'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Binary
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminDatasourceToolkit::Decorators
      include ForestAdminDatasourceToolkit::Schema

      describe BinaryCollectionDecorator do
        include_context 'with caller'

        subject(:binary_collection_decorator) { described_class }

        let(:book_record) do
          {
            'id' => BinaryHelper.hex_to_bin('30303030'),
            # 1x1 transparent png (we use it to test that the datauri can guess mime types)
            'cover' => Base64.strict_decode64('R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw=='),
            'author' => {
              'name' => 'John Doe',
              # Invalid image file (the datauri should not be able to guess the mime type)
              'picture' => BinaryHelper.hex_to_bin('30303030'),
              'tags' => %w[tag1 tag2]
            }
          }
        end

        let(:favorite_record) { { 'id' => 1, 'book' => book_record } }

        before do
          datasource = Datasource.new
          @collection_favorite = collection_build(
            name: 'favorite',
            schema: {
              fields: {
                'id' => numeric_primary_key_build,
                'book' => many_to_one_build(foreign_key: 'book_id', foreign_collection: 'book')
              }
            }
          )
          @collection_book = collection_build(
            name: 'book',
            schema: {
              fields: {
                'id' => column_build(
                  is_primary_key: true,
                  column_type: 'Binary',
                  validations: [
                    { operator: Operators::LONGER_THAN, value: 15 },
                    { operator: Operators::SHORTER_THAN, value: 17 },
                    { operator: Operators::PRESENT },
                    { operator: Operators::NOT_EQUAL, value: BinaryHelper.hex_to_bin('1234') }
                  ]
                ),
                'title' => column_build,
                'cover' => column_build(column_type: 'Binary'),
                'author' => column_build(column_type: { 'name' => 'String', 'picture' => 'Binary', 'tags' => ['String'] })
              }
            }
          )

          @collection_comment = collection_build(
            name: 'comment',
            schema: {
              fields: {
                'id' => numeric_primary_key_build,
                'commentable_id' => column_build(column_type: 'Number'),
                'commentable_type' => column_build,
                'commentable' => Relations::PolymorphicManyToOneSchema.new(
                  foreign_key_type_field: 'commentable_type',
                  foreign_collections: %w[book],
                  foreign_key_targets: { 'book' => 'id' },
                  foreign_key: 'commentable_id'
                )
              }
            }
          )

          datasource.add_collection(@collection_favorite)
          datasource.add_collection(@collection_book)
          datasource.add_collection(@collection_comment)

          @datasource_decorator = DatasourceDecorator.new(datasource, binary_collection_decorator)
          @decorated_favorite = @datasource_decorator.get_collection('favorite')
          @decorated_book = @datasource_decorator.get_collection('book')
        end

        describe 'set_binary_mode' do
          it 'raise an error when an invalid mode is provided' do
            expect { @decorated_book.set_binary_mode('name', 'invalid') }.to raise_error(Exceptions::ForestException)
          end

          it 'raise an error when the field does not exist' do
            expect { @decorated_book.set_binary_mode('invalid', 'hex') }.to raise_error(Exceptions::ForestException)
          end

          it 'raise an error when the field is not a binary field' do
            expect { @decorated_book.set_binary_mode('title', 'hex') }.to raise_error(Exceptions::ForestException)
          end
        end

        describe 'schema' do
          it 'do not modified the favorite collection schema' do
            expect(@collection_favorite.schema[:fields]['id'].column_type).to eq(@decorated_favorite.schema[:fields]['id'].column_type)
            expect(@collection_favorite.schema[:fields]['id'].validations).to eq(@decorated_favorite.schema[:fields]['id'].validations)
          end

          it 'rewrite book primary key as an hex string' do
            expect(@decorated_book.schema[:fields]['id']).to have_attributes(
              is_primary_key: true,
              column_type: 'String',
              validations: [
                { operator: Operators::MATCH, value: '/^[0-9a-f]+$/' },
                { operator: Operators::LONGER_THAN, value: 31 },
                { operator: Operators::SHORTER_THAN, value: 33 },
                { operator: Operators::PRESENT }
              ]
            )
          end

          it 'rewrite book cover as datauri' do
            expect(@decorated_book.schema[:fields]['cover']).to have_attributes(
              column_type: 'String',
              validations: [{ operator: Operators::MATCH, value: '/^data:.*;base64,.*/' }]
            )
          end

          it 'rewrite book author picture but validation left alone' do
            expect(@decorated_book.schema[:fields]['author']).to have_attributes(
              column_type: { 'name' => 'String', 'picture' => 'String', 'tags' => ['String'] }
            )
          end

          it 'rewrite book cover as hex string if requested' do
            @decorated_book.set_binary_mode('cover', 'hex')

            expect(@decorated_book.schema[:fields]['cover']).to have_attributes(
              column_type: 'String',
              validations: [{ operator: Operators::MATCH, value: '/^[0-9a-f]+$/' }]
            )
          end
        end

        describe 'list with a simple filter' do
          #  Build params (30303030 is the hex representation of 0000)
          let(:condition_tree) { Nodes::ConditionTreeLeaf.new('id', Operators::EQUAL, '30303030') }
          let(:filter) { Filter.new(condition_tree: condition_tree) }
          let(:projection) { Projection.new(%w[id cover author:picture]) }

          before do
            allow(@collection_book).to receive(:list).and_return([book_record])
          end

          it 'refine filter when call list' do
            @decorated_book.list(caller, filter, projection)

            expect(@collection_book).to have_received(:list) do |_caller, filter, _projection|
              expect(filter.condition_tree.to_h).to eq(
                { field: 'id', operator: Operators::EQUAL, value: '0000' }
              )
            end
          end

          it 'transformed records when call list' do
            records = @decorated_book.list(caller, filter, projection)

            expect(records).to eq(
              [
                {
                  'id' => '30303030',
                  'cover' => 'data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==',
                  'author' => {
                    'name' => 'John Doe',
                    'picture' => 'data:application/octet-stream;base64,MDAwMA==',
                    'tags' => %w[tag1 tag2]
                  }
                }
              ]
            )
          end
        end

        describe 'list with a more complex filter' do
          #  Build params (30303030 is the hex representation of 0000)
          let(:condition_tree) do
            Nodes::ConditionTreeBranch.new(
              'Or',
              [
                Nodes::ConditionTreeLeaf.new('id', Operators::EQUAL, '30303030'),
                Nodes::ConditionTreeLeaf.new('id', Operators::IN, ['30303030']),
                Nodes::ConditionTreeLeaf.new('title', Operators::EQUAL, 'Foundation'),
                Nodes::ConditionTreeLeaf.new('title', Operators::LIKE, 'Found%'),
                Nodes::ConditionTreeLeaf.new('cover', Operators::EQUAL, 'data:image/gif;base64,1234')
              ]
            )
          end
          let(:filter) { Filter.new(condition_tree: condition_tree) }
          let(:projection) { Projection.new(%w[id cover author:picture]) }

          before do
            allow(@collection_book).to receive(:list).and_return([book_record])
          end

          it 'refine filter when call list' do
            @decorated_book.list(caller, filter, projection)

            expect(@collection_book).to have_received(:list) do |_caller, filter, _projection|
              expect(filter.condition_tree.to_h).to eq(
                {
                  aggregator: 'Or',
                  conditions: [
                    { field: 'id', operator: Operators::EQUAL, value: BinaryHelper.hex_to_bin('30303030') },
                    { field: 'id', operator: Operators::IN, value: [BinaryHelper.hex_to_bin('30303030')] },
                    { field: 'title', operator: Operators::EQUAL, value: 'Foundation' },
                    { field: 'title', operator: Operators::LIKE, value: 'Found%' },
                    { field: 'cover', operator: Operators::EQUAL, value: Base64.strict_decode64('1234') }
                  ]
                }
              )
            end
          end
        end

        describe 'list from relations' do
          #  Build params (30303030 is the hex representation of 0000)
          let(:condition_tree) { Nodes::ConditionTreeLeaf.new('book:id', Operators::EQUAL, '30303030') }
          let(:filter) { Filter.new(condition_tree: condition_tree) }
          let(:projection) { Projection.new(%w[id book:id book:cover book:author:picture]) }

          before do
            allow(@collection_favorite).to receive(:list).and_return([favorite_record, { 'id' => 2, 'book' => nil }])
          end

          it 'refine filter when call list' do
            @decorated_favorite.list(caller, filter, projection)

            expect(@collection_favorite).to have_received(:list) do |_caller, filter, _projection|
              expect(filter.condition_tree.to_h).to eq(
                { field: 'book:id', operator: Operators::EQUAL, value: BinaryHelper.hex_to_bin('30303030') }
              )
            end
          end

          it 'transformed records when call list' do
            records = @decorated_favorite.list(caller, filter, projection)

            expect(records).to eq(
              [
                {
                  'id' => 1,
                  'book' => {
                    'id' => '30303030',
                    'cover' => 'data:image/gif;base64,R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==',
                    'author' => {
                      'name' => 'John Doe',
                      'picture' => 'data:application/octet-stream;base64,MDAwMA==',
                      'tags' => %w[tag1 tag2]
                    }
                  }
                },
                {
                  'id' => 2,
                  'book' => nil
                }
              ]
            )
          end

          it 'not transformed records when call list from polymorphic many to one' do
            allow(@datasource_decorator.get_collection('comment')).to receive(:list)
              .and_return([
                            {
                              'id' => 1,
                              'commentable_id' => 1,
                              'commentable_type' => 'book',
                              'commentable' => book_record
                            }
                          ])

            records = @datasource_decorator.get_collection('comment')
                                           .list(
                                             caller,
                                             Filter.new,
                                             Projection.new(%w[id addressable:*])
                                           )

            expect(records).to eq(
              [
                {
                  'id' => 1,
                  'commentable_id' => 1,
                  'commentable_type' => 'book',
                  'commentable' => book_record
                }
              ]
            )
          end
        end

        describe 'simple creation' do
          let(:record) { { 'id' => '3030', 'cover' => 'data:application/octet-stream;base64,aGVsbG8=' } }

          before do
            allow(@collection_book).to receive(:create)
              .and_return(
                { 'id' => BinaryHelper.hex_to_bin('3030'), 'cover' => Base64.strict_decode64('aGVsbG8=') }
              )
          end

          it 'transformed record when going to database' do
            @decorated_book.create(caller, record)

            expect(@collection_book).to have_received(:create) do |_caller, data|
              expect(data).to eq(
                { 'id' => BinaryHelper.hex_to_bin('3030'), 'cover' => Base64.strict_decode64('aGVsbG8=') }
              )
            end
          end

          it 'transformed record return for frontend' do
            data = @decorated_book.create(caller, record)

            expect(data).to eq(record)
          end
        end

        describe 'simple update' do
          let(:patch) { { 'cover' => 'data:image/gif;base64,aGVsbG8=' } }

          it 'transformed patch when going to database' do
            @decorated_book.update(caller, Filter.new, { 'cover' => 'data:image/gif;base64,aGVsbG8=' })

            expect(@collection_book).to have_received(:update) do |_caller, _filter, data|
              expect(data).to eq(
                { 'cover' => Base64.strict_decode64('aGVsbG8=') }
              )
            end
          end
        end

        describe 'aggregation with binary groups' do
          it 'transformed groups in result' do
            aggregation = Aggregation.new(operation: 'Count', field: 'title', groups: [{ field: 'cover' }])
            allow(@collection_book).to receive(:aggregate)
              .and_return([{ 'value' => 1, 'group' => { 'cover' => Base64.strict_decode64('aGVsbG8=') } }])
            result = @decorated_book.aggregate(caller, Filter.new, aggregation)

            expect(result).to eq(
              [
                { 'value' => 1, 'group' => { 'cover' => 'data:application/octet-stream;base64,aGVsbG8=' } }
              ]
            )
          end
        end

        describe 'aggregation from a relation' do
          it 'transformed groups in result' do
            aggregation = Aggregation.new(operation: 'Count', field: 'title', groups: [{ field: 'book:cover' }])
            allow(@collection_favorite).to receive(:aggregate)
              .and_return([{ 'value' => 1, 'group' => { 'book:cover' => Base64.strict_decode64('aGVsbG8=') } }])
            result = @decorated_favorite.aggregate(caller, Filter.new, aggregation)

            expect(result).to eq(
              [
                { 'value' => 1, 'group' => { 'book:cover' => 'data:application/octet-stream;base64,aGVsbG8=' } }
              ]
            )
          end
        end
      end
    end
  end
end
