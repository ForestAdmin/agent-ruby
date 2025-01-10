require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Components
    module Query
      include ForestAdminDatasourceToolkit::Schema
      include ForestAdminDatasourceToolkit::Schema::Relations
      describe ProjectionFactory do
        describe 'with one to one and many to one relations' do
          before do
            @datasource = build_datasource_with_collections(
              [
                build_collection(
                  {
                    name: 'Book',
                    schema: {
                      fields: {
                        'id' => ColumnSchema.new(column_type: PrimitiveType::NUMBER, is_primary_key: true),
                        'my_author' => OneToOneSchema.new(
                          origin_key: 'book_id',
                          origin_key_target: 'id',
                          foreign_collection: 'Author'
                        ),
                        'format_id' => ColumnSchema.new(column_type: PrimitiveType::NUMBER),
                        'my_format' => ManyToOneSchema.new(
                          foreign_key: 'format_id',
                          foreign_key_target: 'id',
                          foreign_collection: 'Format'
                        ),
                        'title' => ColumnSchema.new(column_type: PrimitiveType::STRING)
                      }
                    }
                  }
                ),
                build_collection(
                  {
                    name: 'Author',
                    schema: {
                      fields: {
                        'id' => ColumnSchema.new(column_type: PrimitiveType::NUMBER, is_primary_key: true),
                        'book_id' => ColumnSchema.new(column_type: PrimitiveType::NUMBER),
                        'name' => ColumnSchema.new(column_type: PrimitiveType::STRING)
                      }
                    }
                  }
                ),
                build_collection(
                  {
                    name: 'Format',
                    schema: {
                      fields: {
                        'id' => ColumnSchema.new(column_type: PrimitiveType::NUMBER, is_primary_key: true),
                        'name' => ColumnSchema.new(column_type: PrimitiveType::STRING)
                      }
                    }
                  }
                )
              ]
            )
          end

          describe 'all' do
            it 'return all the collection fields and the relation fields' do
              collection = @datasource.get_collection('Book')

              expect(described_class.all(collection)).to eq(
                %w[id my_author:id my_author:book_id my_author:name format_id my_format:id my_format:name title]
              )
            end
          end
        end

        describe 'with other relations' do
          before do
            @datasource = build_datasource_with_collections(
              [
                build_collection(
                  {
                    name: 'Book',
                    schema: {
                      fields: {
                        'id' => ColumnSchema.new(column_type: PrimitiveType::NUMBER, is_primary_key: true),
                        'my_book_persons' => OneToManySchema.new(
                          origin_key: 'book_id',
                          origin_key_target: 'id',
                          foreign_collection: 'Person'
                        ),
                        'title' => ColumnSchema.new(column_type: PrimitiveType::STRING)
                      }
                    }
                  }
                ),
                build_collection(
                  {
                    name: 'Person',
                    schema: {
                      fields: { 'id' => ColumnSchema.new(column_type: PrimitiveType::NUMBER, is_primary_key: true) }
                    }
                  }
                )
              ]
            )
          end

          describe 'all' do
            it 'return all the collection fields without the relations' do
              collection = @datasource.get_collection('Book')

              expect(described_class.all(collection)).to eq(
                %w[id title]
              )
            end
          end
        end

        describe 'with polymorphic one to one and polymorphic many to one relations' do
          before do
            @datasource = build_datasource_with_collections(
              [
                build_collection(
                  {
                    name: 'Address',
                    schema: {
                      fields: {
                        'id' => ColumnSchema.new(column_type: PrimitiveType::NUMBER, is_primary_key: true),
                        'addressable_id' => ColumnSchema.new(column_type: 'Number'),
                        'addressable_type' => ColumnSchema.new(column_type: 'String'),
                        'addressable' => Relations::PolymorphicManyToOneSchema.new(
                          foreign_key_type_field: 'addressable_type',
                          foreign_collections: ['User'],
                          foreign_key_targets: { 'User' => 'id' },
                          foreign_key: 'addressable_id'
                        )
                      }
                    }
                  }
                ),
                build_collection(
                  {
                    name: 'User',
                    schema: {
                      fields: {
                        'id' => ColumnSchema.new(column_type: PrimitiveType::NUMBER, is_primary_key: true),
                        'address' => Relations::PolymorphicOneToOneSchema.new(
                          origin_key: 'addressable_id',
                          foreign_collection: 'Address',
                          origin_key_target: 'id',
                          origin_type_field: 'addressable_type',
                          origin_type_value: 'User'
                        )
                      }
                    }
                  }
                )
              ]
            )
          end

          describe 'all' do
            it 'return all the collection fields and the relation fields' do
              collection = @datasource.get_collection('User')

              expect(described_class.all(collection)).to eq(
                %w[id address:id address:addressable_id address:addressable_type]
              )
            end

            it 'return all the collection fields and replace PolymorphicManyToOne with :*' do
              collection = @datasource.get_collection('Address')

              expect(described_class.all(collection)).to eq(
                %w[id addressable_id addressable_type addressable:*]
              )
            end
          end
        end
      end
    end
  end
end
