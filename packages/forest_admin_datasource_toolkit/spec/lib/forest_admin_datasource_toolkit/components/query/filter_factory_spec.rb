require 'spec_helper'
require 'active_support/all'
require 'active_support/core_ext/numeric/time'

module ForestAdminDatasourceToolkit
  module Components
    module Query
      include ConditionTree
      include ConditionTree::Nodes
      include Schema
      include Schema::Relations

      describe FilterFactory do
        include_context 'with caller'

        let(:timezone) { 'Europe/Paris' }

        context 'when call get_previous_period_filter' do
          it 'when no interval operator is present in the condition tree should not modify the condition tree' do
            leaf = ConditionTreeLeaf.new('someField', 'Like', 'someValue')
            filter = Filter.new(condition_tree: leaf)
            expect(described_class.get_previous_period_filter(filter, timezone).to_h).to eq(filter.to_h)
          end

          it 'overrides baseOperator by previousOperator' do
            operators = [
              { base: Operators::TODAY, previous: Operators::YESTERDAY },
              { base: Operators::PREVIOUS_WEEK_TO_DATE, previous: Operators::PREVIOUS_WEEK },
              { base: Operators::PREVIOUS_MONTH_TO_DATE, previous: Operators::PREVIOUS_MONTH },
              { base: Operators::PREVIOUS_QUARTER_TO_DATE, previous: Operators::PREVIOUS_QUARTER },
              { base: Operators::PREVIOUS_YEAR_TO_DATE, previous: Operators::PREVIOUS_YEAR }
            ]

            operators.each do |operator|
              filter = Filter.new(condition_tree: ConditionTreeLeaf.new('someField', operator[:base], 'someValue'))
              expect(described_class.get_previous_period_filter(filter, timezone).condition_tree.to_h)
                .to eq(ConditionTreeLeaf.new('someField', operator[:previous], 'someValue').to_h)
            end
          end

          it 'replaces baseOperator by a greater/less than operator' do
            operators = [
              { base: Operators::YESTERDAY, unit: 'Day' },
              { base: Operators::PREVIOUS_WEEK, unit: 'Week' },
              { base: Operators::PREVIOUS_MONTH, unit: 'Month' },
              { base: Operators::PREVIOUS_QUARTER, unit: 'Quarter' },
              { base: Operators::PREVIOUS_YEAR, unit: 'Year' }
            ]

            operators.each do |operator|
              filter = Filter.new(condition_tree: ConditionTreeLeaf.new('someField', operator[:base], 'someValue'))
              start = "beginning_of_#{operator[:unit].downcase}"
              end_ = "end_of_#{operator[:unit].downcase}"
              start_period = Time.now.in_time_zone(timezone)
                                 .send(:"prev_#{operator[:unit].downcase}")
                                 .send(start)
                                 .to_datetime
                                 .strftime('%Y-%m-%d %H:%M:%S')
              end_period = Time.now.in_time_zone(timezone)
                               .send(:"prev_#{operator[:unit].downcase}")
                               .send(end_)
                               .to_datetime
                               .strftime('%Y-%m-%d %H:%M:%S')

              expect(described_class.get_previous_period_filter(filter, timezone).condition_tree.to_h)
                .to eq(ConditionTreeBranch.new(
                  'And',
                  [
                    ConditionTreeLeaf.new('someField', Operators::GREATER_THAN, start_period),
                    ConditionTreeLeaf.new('someField', Operators::LESS_THAN, end_period)
                  ]
                ).to_h)
            end
          end

          it 'replaces PreviousXDaysToDate operator by a greater/less than' do
            filter = Filter.new(condition_tree: ConditionTreeLeaf.new('someField', Operators::PREVIOUS_X_DAYS_TO_DATE,
                                                                      3))
            start_period = Time.now.in_time_zone(timezone).prev_day(2 * filter.condition_tree.value)
                               .beginning_of_day
                               .to_datetime
                               .strftime('%Y-%m-%d %H:%M:%S')
            end_period = Time.now.in_time_zone(timezone).prev_day(filter.condition_tree.value)
                             .to_datetime
                             .strftime('%Y-%m-%d %H:%M:%S')

            expect(described_class.get_previous_period_filter(filter, timezone).condition_tree.to_h)
              .to eq(ConditionTreeBranch.new(
                'And',
                [
                  ConditionTreeLeaf.new('someField', Operators::GREATER_THAN, start_period),
                  ConditionTreeLeaf.new('someField', Operators::LESS_THAN, end_period)
                ]
              ).to_h)
          end

          it 'replaces PreviousXDays operator by a greater/less than' do
            filter = Filter.new(condition_tree: ConditionTreeLeaf.new('someField', Operators::PREVIOUS_X_DAYS, 3))
            start_period = Time.now.in_time_zone(timezone).prev_day(filter.condition_tree.value * 2)
                               .beginning_of_day
                               .to_datetime
                               .strftime('%Y-%m-%d %H:%M:%S')
            end_period = Time.now.in_time_zone(timezone).prev_day(filter.condition_tree.value)
                             .beginning_of_day
                             .to_datetime
                             .strftime('%Y-%m-%d %H:%M:%S')

            expect(described_class.get_previous_period_filter(filter, timezone).condition_tree.to_h)
              .to eq(ConditionTreeBranch.new(
                'And',
                [
                  ConditionTreeLeaf.new('someField', Operators::GREATER_THAN, start_period),
                  ConditionTreeLeaf.new('someField', Operators::LESS_THAN, end_period)
                ]
              ).to_h)
          end
        end

        context 'when call make_through_filter' do
          let(:datasource) { Datasource.new }
          let(:collection_book) do
            collection = ForestAdminDatasourceToolkit::Collection.new(datasource, 'Book')
            collection.add_fields(
              {
                'id' => ColumnSchema.new(column_type: PrimitiveType::NUMBER, is_primary_key: true),
                'reviews' => ManyToManySchema.new(
                  origin_key: 'book_id',
                  origin_key_target: 'id',
                  foreign_key: 'review_id',
                  foreign_key_target: 'id',
                  foreign_collection: 'Review',
                  through_collection: 'BookReview'
                ),
                'bookReviews' => OneToManySchema.new(
                  origin_key: 'book_id',
                  origin_key_target: 'id',
                  foreign_collection: 'Review'
                )
              }
            )

            return collection
          end

          let(:collection_review) do
            collection = ForestAdminDatasourceToolkit::Collection.new(datasource, 'Review')
            collection.add_fields(
              {
                'id' => ColumnSchema.new(column_type: PrimitiveType::NUMBER, is_primary_key: true)
              }
            )

            return collection
          end

          let(:collection_book_review) do
            collection = ForestAdminDatasourceToolkit::Collection.new(datasource, 'BookReview')
            collection.add_fields(
              {
                'id' => ColumnSchema.new(column_type: PrimitiveType::NUMBER, is_primary_key: true),
                'review_id' => ColumnSchema.new(column_type: PrimitiveType::NUMBER, filter_operators: [Operators::PRESENT]),
                'review' => ManyToOneSchema.new(
                  foreign_key: 'review_id',
                  foreign_key_target: 'id',
                  foreign_collection: 'Review'
                ),
                'book_id' => ColumnSchema.new(column_type: PrimitiveType::NUMBER),
                'book' => ManyToOneSchema.new(
                  foreign_key: 'book_id',
                  foreign_key_target: 'id',
                  foreign_collection: 'Book'
                )
              }
            )

            return collection
          end

          before do
            datasource.add_collection(collection_book)
            datasource.add_collection(collection_review)
            datasource.add_collection(collection_book_review)

            allow(collection_review).to receive(:list).and_return([{ 'id' => 1 }, { 'id' => 2 }])
            allow(collection_book_review).to receive(:list).and_return([{ 'id' => 123, 'review_id' => 1 },
                                                                        { 'id' => 124, 'review_id' => 2 }])
          end

          it 'nests the provided filter many to many' do
            base_filter = Filter.new(condition_tree: ConditionTreeLeaf.new('someField', Operators::EQUAL, 1))
            filter = described_class.make_through_filter(collection_book, [1], 'reviews', caller, base_filter)

            expect(filter.condition_tree.to_h).to eq(
              ConditionTreeBranch.new(
                'And',
                [
                  ConditionTreeLeaf.new('book_id', Operators::EQUAL, 1),
                  ConditionTreeLeaf.new('review:someField', Operators::EQUAL, 1),
                  ConditionTreeLeaf.new('review_id', Operators::PRESENT)
                ]
              ).to_h
            )
          end

          it 'makes two queries many to many' do
            base_filter = Filter.new(condition_tree: ConditionTreeLeaf.new('someField', Operators::EQUAL, 1),
                                     segment: 'someSegment')
            filter = described_class.make_through_filter(collection_book, [1], 'reviews', caller, base_filter)

            expect(filter.condition_tree.to_h).to eq(
              ConditionTreeBranch.new(
                'And',
                [
                  ConditionTreeLeaf.new('book_id', Operators::EQUAL, 1),
                  ConditionTreeLeaf.new('review_id', Operators::IN, [1, 2])
                ]
              ).to_h
            )
          end

          it 'adds the fk condition one to many' do
            base_filter = Filter.new(condition_tree: ConditionTreeLeaf.new('someField', Operators::EQUAL, 1),
                                     segment: 'someSegment')
            filter = described_class.make_foreign_filter(collection_book, [1], 'bookReviews', caller, base_filter)

            expect(filter.segment).to eq('someSegment')
            expect(filter.condition_tree.to_h).to eq(
              ConditionTreeBranch.new(
                'And',
                [
                  ConditionTreeLeaf.new('someField', Operators::EQUAL, 1),
                  ConditionTreeLeaf.new('book_id', Operators::EQUAL, 1)
                ]
              ).to_h
            )
          end
        end

        context 'when call make_foreign_filter' do
          before do
            @datasource = build_datasource_with_collections(
              [
                build_collection(
                  {
                    name: 'Book',
                    schema: {
                      fields: {
                        'id' => ColumnSchema.new(column_type: PrimitiveType::NUMBER, is_primary_key: true),
                        'reviews' => ManyToManySchema.new(
                          origin_key: 'book_id',
                          origin_key_target: 'id',
                          foreign_key: 'review_id',
                          foreign_key_target: 'id',
                          foreign_collection: 'Review',
                          through_collection: 'BookReview'
                        ),
                        'book_reviews' => OneToManySchema.new(
                          origin_key: 'book_id',
                          origin_key_target: 'id',
                          foreign_collection: 'Review'
                        ),
                        'book_reviews_poly' => PolymorphicOneToManySchema.new(
                          origin_key: 'book_id',
                          foreign_collection: 'Review',
                          origin_key_target: 'id',
                          origin_type_field: 'reviewable_type',
                          origin_type_value: 'Book'
                        )
                      }
                    }
                  }
                ),
                build_collection(
                  {
                    name: 'Review',
                    schema: {
                      fields: {
                        'id' => ColumnSchema.new(column_type: PrimitiveType::NUMBER, is_primary_key: true),
                        'reviewable_id' => ColumnSchema.new(column_type: PrimitiveType::NUMBER),
                        'reviewable_type' => ColumnSchema.new(column_type: PrimitiveType::STRING),
                        'reviewable' => PolymorphicManyToOneSchema.new(
                          foreign_key_type_field: 'reviewable_type',
                          foreign_collections: %w[Book],
                          foreign_key_targets: { 'Book' => 'id' },
                          foreign_key: 'reviewable_id'
                        )
                      }
                    }
                  }
                ),
                build_collection(
                  {
                    name: 'BookReview',
                    schema: {
                      fields: {
                        'id' => ColumnSchema.new(column_type: PrimitiveType::NUMBER, is_primary_key: true),
                        'book_id' => ColumnSchema.new(column_type: PrimitiveType::NUMBER),
                        'review_id' => ColumnSchema.new(column_type: PrimitiveType::NUMBER),
                        'review' => ManyToOneSchema.new(
                          foreign_key: 'review_id',
                          foreign_key_target: 'id',
                          foreign_collection: 'Review'
                        )
                      }
                    }
                  }
                )
              ]
            )
          end

          it 'add the fk condition [one to many]' do
            book = @datasource.get_collection('Book')
            base_filter = Filter.new(
              condition_tree: ConditionTreeLeaf.new('some_field', Operators::EQUAL, 1),
              segment: 'some-segment'
            )

            filter = described_class.make_foreign_filter(book, [1], 'book_reviews', caller, base_filter)
            expect(filter.condition_tree.to_h).to eq(
              {
                aggregator: 'And',
                conditions: [
                  { field: 'some_field', operator: 'equal', value: 1 },
                  { field: 'book_id', operator: 'equal', value: 1 }
                ]
              }
            )
            expect(filter.segment).to eq('some-segment')
          end

          it 'query the through collection [many to many]' do
            book = @datasource.get_collection('Book')
            book_review = @datasource.get_collection('BookReview')
            allow(book_review).to receive(:list).and_return([{ 'review_id' => 123 }, { 'review_id' => 124 }])

            base_filter = Filter.new(
              condition_tree: ConditionTreeLeaf.new('some_field', Operators::EQUAL, 1),
              segment: 'some-segment'
            )

            filter = described_class.make_foreign_filter(book, [1], 'reviews', caller, base_filter)

            expect(book_review).to have_received(:list) do |_caller, through_filter|
              expect(through_filter.condition_tree.to_h).to eq(
                {
                  aggregator: 'And',
                  conditions: [
                    { field: 'book_id', operator: 'equal', value: 1 },
                    { field: 'review_id', operator: 'present', value: nil }
                  ]
                }
              )
            end

            expect(filter.condition_tree.to_h).to eq(
              {
                aggregator: 'And',
                conditions: [
                  { field: 'some_field', operator: 'equal', value: 1 },
                  { field: 'id', operator: 'in', value: [123, 124] }
                ]
              }
            )
            expect(filter.segment).to eq('some-segment')
          end

          it 'add the fk condition and type [polymorphic one to many]' do
            book = @datasource.get_collection('Book')
            base_filter = Filter.new(
              condition_tree: ConditionTreeLeaf.new('some_field', Operators::EQUAL, 1),
              segment: 'some-segment'
            )

            filter = described_class.make_foreign_filter(book, [1], 'book_reviews_poly', caller, base_filter)
            expect(filter.condition_tree.to_h).to eq(
              {
                aggregator: 'And',
                conditions: [
                  { field: 'some_field', operator: 'equal', value: 1 },
                  { field: 'book_id', operator: 'equal', value: 1 },
                  { field: 'reviewable_type', operator: 'equal', value: 'Book' }
                ]
              }
            )
            expect(filter.segment).to eq('some-segment')
          end
        end
      end
    end
  end
end
