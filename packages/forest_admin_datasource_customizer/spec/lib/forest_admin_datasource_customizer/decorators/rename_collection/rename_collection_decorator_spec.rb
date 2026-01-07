require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module RenameCollection
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminDatasourceToolkit::Decorators
      include ForestAdminDatasourceToolkit::Schema

      describe RenameCollectionDecorator do
        include_context 'with caller'

        before do
          @collection_transaction = build_collection(
            name: 'transaction',
            schema: {
              fields: {
                'id' => build_numeric_primary_key,
                'amount' => build_column,
                'subject_id' => build_column,
                'subject_type' => build_column,
                'subject' => Relations::PolymorphicManyToOneSchema.new(
                  foreign_key_type_field: 'subject_type',
                  foreign_collections: ['income', 'expense'],
                  foreign_key_targets: { 'income' => 'id', 'expense' => 'id' },
                  foreign_key: 'subject_id'
                )
              }
            }
          )

          @collection_income = build_collection(
            name: 'income',
            schema: {
              fields: {
                'id' => build_numeric_primary_key,
                'description' => build_column,
                'transactions' => Relations::PolymorphicOneToManySchema.new(
                  origin_key: 'subject_id',
                  foreign_collection: 'transaction',
                  origin_key_target: 'id',
                  origin_type_field: 'subject_type',
                  origin_type_value: 'income'
                )
              }
            }
          )

          @collection_expense = build_collection(
            name: 'expense',
            schema: {
              fields: {
                'id' => build_numeric_primary_key,
                'description' => build_column,
                'transactions' => Relations::PolymorphicOneToManySchema.new(
                  origin_key: 'subject_id',
                  foreign_collection: 'transaction',
                  origin_key_target: 'id',
                  origin_type_field: 'subject_type',
                  origin_type_value: 'expense'
                )
              }
            }
          )

          @datasource = RenameCollectionDatasourceDecorator.new(
            build_datasource_with_collections([
                                                @collection_transaction,
                                                @collection_income,
                                                @collection_expense
                                              ])
          )
        end

        describe '#name' do
          it 'returns the renamed collection name' do
            @datasource.rename_collection('income', 'renamed_income')
            collection = @datasource.get_collection('renamed_income')

            expect(collection.name).to eq('renamed_income')
          end
        end

        describe '#list' do
          context 'with polymorphic relations' do
            it 'transforms polymorphic type values in returned records' do
              @datasource.rename_collection('income', 'renamed_income')
              collection = @datasource.get_collection('transaction')

              # Mock the child collection to return records with old collection names
              allow(collection.instance_variable_get(:@child_collection)).to receive(:list).and_return([
                                                                                                         { 'id' => 1, 'amount' => 100, 'subject_id' => 1, 'subject_type' => 'income' }
                                                                                                       ])

              result = collection.list(caller, nil, nil)

              expect(result).to eq([
                                     { 'id' => 1, 'amount' => 100, 'subject_id' => 1, 'subject_type' => 'renamed_income' }
                                   ])
            end

            it 'handles arrays of records' do
              @datasource.rename_collection('income', 'renamed_income')
              @datasource.rename_collection('expense', 'renamed_expense')
              collection = @datasource.get_collection('transaction')

              allow(collection.instance_variable_get(:@child_collection)).to receive(:list).and_return([
                                                                                                         { 'id' => 1, 'amount' => 100, 'subject_id' => 1, 'subject_type' => 'income' },
                                                                                                         { 'id' => 2, 'amount' => 200, 'subject_id' => 2, 'subject_type' => 'expense' }
                                                                                                       ])

              result = collection.list(caller, nil, nil)

              expect(result).to eq([
                                     { 'id' => 1, 'amount' => 100, 'subject_id' => 1, 'subject_type' => 'renamed_income' },
                                     { 'id' => 2, 'amount' => 200, 'subject_id' => 2, 'subject_type' => 'renamed_expense' }
                                   ])
            end
          end
        end

        describe '#create' do
          context 'with polymorphic relations' do
            it 'transforms polymorphic type values before creating' do
              @datasource.rename_collection('income', 'renamed_income')
              collection = @datasource.get_collection('transaction')
              child_collection = collection.instance_variable_get(:@child_collection)

              # Setup spy for child collection
              allow(child_collection).to receive(:create).with(
                caller,
                { 'amount' => 100, 'subject_id' => 1, 'subject_type' => 'income' }
              ).and_return(
                { 'id' => 1, 'amount' => 100, 'subject_id' => 1, 'subject_type' => 'income' }
              )

              result = collection.create(caller, { 'amount' => 100, 'subject_id' => 1, 'subject_type' => 'renamed_income' })

              expect(result).to eq({ 'id' => 1, 'amount' => 100, 'subject_id' => 1, 'subject_type' => 'renamed_income' })
              expect(child_collection).to have_received(:create).with(
                caller,
                { 'amount' => 100, 'subject_id' => 1, 'subject_type' => 'income' }
              )
            end
          end
        end

        describe '#update' do
          context 'with polymorphic relations' do
            it 'transforms polymorphic type values in patch' do
              @datasource.rename_collection('income', 'renamed_income')
              collection = @datasource.get_collection('transaction')
              child_collection = collection.instance_variable_get(:@child_collection)
              filter = Filter.new

              allow(child_collection).to receive(:update)

              collection.update(caller, filter, { 'subject_type' => 'renamed_income' })

              expect(child_collection).to have_received(:update).with(
                caller,
                filter,
                { 'subject_type' => 'income' }
              )
            end
          end
        end

        describe '#refine_filter' do
          context 'with polymorphic type fields in condition tree' do
            it 'transforms renamed collection names to original names' do
              @datasource.rename_collection('income', 'renamed_income')
              collection = @datasource.get_collection('transaction')

              filter = Filter.new(
                condition_tree: Nodes::ConditionTreeLeaf.new('subject_type', Operators::EQUAL, 'renamed_income')
              )

              refined_filter = collection.refine_filter(caller, filter)

              expect(refined_filter.condition_tree.value).to eq('income')
            end

            it 'handles array values (IN operator)' do
              @datasource.rename_collection('income', 'renamed_income')
              @datasource.rename_collection('expense', 'renamed_expense')
              collection = @datasource.get_collection('transaction')

              filter = Filter.new(
                condition_tree: Nodes::ConditionTreeLeaf.new('subject_type', Operators::IN, ['renamed_income', 'renamed_expense'])
              )

              refined_filter = collection.refine_filter(caller, filter)

              expect(refined_filter.condition_tree.value).to eq(['income', 'expense'])
            end

            it 'leaves non-type fields unchanged' do
              @datasource.rename_collection('income', 'renamed_income')
              collection = @datasource.get_collection('transaction')

              filter = Filter.new(
                condition_tree: Nodes::ConditionTreeLeaf.new('amount', Operators::GREATER_THAN, 100)
              )

              refined_filter = collection.refine_filter(caller, filter)

              expect(refined_filter.condition_tree.value).to eq(100)
            end
          end
        end

        describe '#refine_schema' do
          context 'with PolymorphicManyToOne relations' do
            it 'renames foreign_collections' do
              @datasource.rename_collection('income', 'renamed_income')
              @datasource.rename_collection('expense', 'renamed_expense')
              collection = @datasource.get_collection('transaction')

              expect(collection.schema[:fields]['subject'].foreign_collections).to eq(['renamed_income', 'renamed_expense'])
              expect(collection.schema[:fields]['subject'].foreign_key_targets.keys).to eq(['renamed_income', 'renamed_expense'])
            end
          end

          context 'with PolymorphicOneToMany relations' do
            it 'updates origin_type_value when collection is renamed' do
              @datasource.rename_collection('income', 'renamed_income')
              collection = @datasource.get_collection('renamed_income')

              expect(collection.schema[:fields]['transactions'].origin_type_value).to eq('renamed_income')
            end

            it 'updates foreign_collection' do
              @datasource.rename_collection('transaction', 'renamed_transaction')
              collection = @datasource.get_collection('income')

              expect(collection.schema[:fields]['transactions'].foreign_collection).to eq('renamed_transaction')
            end
          end
        end
      end
    end
  end
end
