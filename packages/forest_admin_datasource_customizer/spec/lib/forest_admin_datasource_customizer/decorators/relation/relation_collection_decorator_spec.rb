require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Relation
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminDatasourceToolkit::Decorators
      include ForestAdminDatasourceToolkit::Schema
      include ForestAdminDatasourceToolkit::Exceptions

      describe RelationCollectionDecorator do
        include_context 'with caller'
        subject(:relation_collection_decorator) { described_class }
        let(:passport_records) do
          [
            {
              'id' => 101,
              'issue_date' => '2010-01-01',
              'owner_id' => 202,
              'picture_id' => 301,
              'picture' => { 'picture_id' => 301, 'filename' => 'pic1.jpg' }
            },
            {
              'id' => 102,
              'issue_date' => '2017-01-01',
              'owner_id' => 201,
              'picture_id' => 302,
              'picture' => { 'picture_id' => 302, 'filename' => 'pic2.jpg' }
            },
            {
              'id' => 103,
              'issue_date' => '2017-02-05',
              'owner_id' => nil,
              'picture_id' => 303,
              'picture' => { 'picture_id' => 303, 'filename' => 'pic3.jpg' }
            }
          ]
        end
        let(:person_records) do
          [
            { 'id' => 201, 'other_id' => 201, 'name' => 'Sharon J. Whalen' },
            { 'id' => 202, 'other_id' => 202, 'name' => 'Mae S. Waldron' },
            { 'id' => 203, 'other_id' => 203, 'name' => 'Joseph P. Rodriguez' }
          ]
        end

        before do
          datasource = Datasource.new
          collection_picture = build_collection(
            name: 'picture',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: PrimitiveType::NUMBER, is_primary_key: true, filter_operators: [Operators::EQUAL, Operators::IN]),
                'filename' => ColumnSchema.new(column_type: PrimitiveType::STRING),
                'other_id' => ColumnSchema.new(column_type: PrimitiveType::NUMBER)
              }
            }
          )

          collection_passport = build_collection(
            name: 'passport',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: PrimitiveType::NUMBER, is_primary_key: true, filter_operators: [Operators::EQUAL, Operators::IN]),
                'issue_date' => ColumnSchema.new(column_type: PrimitiveType::DATEONLY),
                'owner_id' => ColumnSchema.new(column_type: PrimitiveType::NUMBER, filter_operators: [Operators::IN]),
                'picture_id' => ColumnSchema.new(column_type: PrimitiveType::NUMBER),
                'picture' => Relations::ManyToOneSchema.new(foreign_key: 'picture_id', foreign_key_target: 'id', foreign_collection: 'picture')
              }
            },
            datasource: datasource
          )

          allow(collection_passport).to receive(:list) do |_caller, filter, projection|
            result = ForestAdminDatasourceToolkit::Utils::HashHelper.convert_keys(passport_records, :to_s)
            result = filter.condition_tree.apply(result, collection_passport, 'Europe/Paris') if filter&.condition_tree
            result = filter.sort.apply(result) if filter&.sort

            projection.apply(result)
          end
          allow(collection_passport).to receive(:aggregate) do |caller, _filter, aggregation, limit|
            aggregation.apply(passport_records, caller.timezone, limit)
          end

          collection_person = build_collection(
            name: 'person',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: PrimitiveType::NUMBER, is_primary_key: true, filter_operators: [Operators::EQUAL, Operators::IN]),
                'other_id' => ColumnSchema.new(column_type: PrimitiveType::NUMBER, filter_operators: [Operators::IN]),
                'name' => ColumnSchema.new(column_type: PrimitiveType::STRING, filter_operators: [Operators::IN])
              }
            },
            datasource: datasource
          )

          allow(collection_person).to receive(:list) do |_caller, filter, projection|
            result = ForestAdminDatasourceToolkit::Utils::HashHelper.convert_keys(person_records, :to_s)
            result = filter.condition_tree.apply(result, collection_person, 'Europe/Paris') if filter&.condition_tree
            result = filter.sort.apply(result) if filter&.sort

            projection.apply(result)
          end
          allow(collection_person).to receive(:aggregate) do |caller, _filter, aggregation, limit|
            aggregation.apply(person_records, caller.timezone, limit)
          end

          datasource.add_collection(collection_picture)
          datasource.add_collection(collection_passport)
          datasource.add_collection(collection_person)

          @datasource_decorator = DatasourceDecorator.new(datasource, relation_collection_decorator)
        end

        context 'when a one to one is declared' do
          context 'when missing dependencies' do
            it 'throws with a non existent fk' do
              expect do
                @datasource_decorator.get_collection('person').add_relation('passport', {
                                                                              type: 'OneToOne',
                                                                              foreign_collection: 'passport',
                                                                              origin_key: '__nonExisting__'
                                                                            })
              end.to raise_error(ForestException, "Column not found: 'passport.__nonExisting__'")
            end
          end

          context 'when missing operators' do
            it 'throws when In is not supported by the fk in the target' do
              expect do
                @datasource_decorator.get_collection('person').add_relation('passport', {
                                                                              type: 'OneToOne',
                                                                              foreign_collection: 'passport',
                                                                              origin_key: 'picture_id'
                                                                            })
              end.to raise_error(ForestException, "Column does not support the In operator: 'passport.picture_id'")
            end
          end

          it 'throws when there is a given originKeyTarget that does not match the target type' do
            expect do
              @datasource_decorator.get_collection('person').add_relation('passport', {
                                                                            type: 'OneToOne',
                                                                            foreign_collection: 'passport',
                                                                            origin_key: 'owner_id',
                                                                            origin_key_target: 'name'
                                                                          })
            end.to raise_error(ForestException, "Types from 'passport.owner_id' and 'person.name' do not match.")
          end

          context 'when there is a given originKeyTarget' do
            it 'registers the relation' do
              expect do
                @datasource_decorator.get_collection('person').add_relation('passport', {
                                                                              type: 'OneToOne',
                                                                              foreign_collection: 'passport',
                                                                              origin_key: 'owner_id',
                                                                              origin_key_target: 'id'
                                                                            })
              end.not_to raise_error
            end
          end

          context 'when there is not a given originKeyTarget' do
            it 'registers the relation' do
              expect do
                @datasource_decorator.get_collection('person').add_relation('passport', {
                                                                              type: 'OneToOne',
                                                                              foreign_collection: 'passport',
                                                                              origin_key: 'owner_id'
                                                                            })
              end.not_to raise_error
            end
          end
        end

        context 'when a one to many is declared' do
          it 'when there is a given originKeyTarget that does not match the target type' do
            expect do
              @datasource_decorator.get_collection('person').add_relation('passport', {
                                                                            type: 'OneToMany',
                                                                            foreign_collection: 'passport',
                                                                            origin_key: 'owner_id',
                                                                            origin_key_target: 'name'
                                                                          })
            end.to raise_error(ForestException, "Types from 'passport.owner_id' and 'person.name' do not match.")
          end

          context 'when there is a given originKeyTarget' do
            it 'registers the relation' do
              expect do
                @datasource_decorator.get_collection('person').add_relation('passport', {
                                                                              type: 'OneToMany',
                                                                              foreign_collection: 'passport',
                                                                              origin_key: 'owner_id',
                                                                              origin_key_target: 'id'
                                                                            })
              end.not_to raise_error
            end
          end

          context 'when there is not a given originKeyTarget' do
            it 'registers the relation' do
              expect do
                @datasource_decorator.get_collection('person').add_relation('passport', {
                                                                              type: 'OneToMany',
                                                                              foreign_collection: 'passport',
                                                                              origin_key: 'owner_id'
                                                                            })
              end.not_to raise_error
            end
          end
        end

        context 'when a many to one is declared' do
          context 'when missing dependencies' do
            it 'throws with a non existent collection' do
              expect do
                @datasource_decorator.get_collection('person').add_relation('someName', {
                                                                              type: 'ManyToOne',
                                                                              foreign_collection: '__nonExisting__',
                                                                              foreign_key: 'owner_id'
                                                                            })
              end.to raise_error(ForestException, 'Collection __nonExisting__ not found.')
            end

            it 'throws with a non existent fk' do
              expect do
                @datasource_decorator.get_collection('passport').add_relation('owner', {
                                                                                type: 'ManyToOne',
                                                                                foreign_collection: 'person',
                                                                                foreign_key: '__nonExisting__'
                                                                              })
              end.to raise_error(ForestException, "Column not found: 'passport.__nonExisting__'")
            end
          end

          context 'when missing operators' do
            it 'throws when In is not supported by the pk in the target' do
              expect do
                @datasource_decorator.get_collection('passport').add_relation('owner', {
                                                                                type: 'ManyToOne',
                                                                                foreign_collection: 'person',
                                                                                foreign_key: 'picture_id'
                                                                              })
              end.to raise_error(ForestException, "Column does not support the In operator: 'passport.picture_id'")
            end
          end

          context 'when there is a given foreignKeyTarget' do
            it 'registers the relation' do
              expect do
                @datasource_decorator.get_collection('passport').add_relation('owner', {
                                                                                type: 'ManyToOne',
                                                                                foreign_collection: 'person',
                                                                                foreign_key: 'owner_id',
                                                                                foreign_key_target: 'id'
                                                                              })
              end.not_to raise_error
            end
          end

          context 'when there is not a given foreignKeyTarget' do
            it 'registers the relation' do
              expect do
                @datasource_decorator.get_collection('passport').add_relation('owner', {
                                                                                type: 'ManyToOne',
                                                                                foreign_collection: 'person',
                                                                                foreign_key: 'owner_id'
                                                                              })
              end.not_to raise_error
            end
          end
        end

        context 'when a many to many is declared' do
          context 'when missing dependencies' do
            it 'throws with a non existent though collection' do
              expect do
                @datasource_decorator.get_collection('person').add_relation('passports', {
                                                                              type: 'ManyToMany',
                                                                              foreign_collection: 'passport',
                                                                              foreign_key: 'owner_id',
                                                                              origin_key: 'owner_id',
                                                                              through_collection: '__nonExisting__'
                                                                            })
              end.to raise_error(ForestException, 'Collection __nonExisting__ not found.')
            end

            it 'throws with a non existent originKey' do
              expect do
                @datasource_decorator.get_collection('person').add_relation('person', {
                                                                              type: 'ManyToMany',
                                                                              foreign_collection: 'passport',
                                                                              foreign_key: 'owner_id',
                                                                              origin_key: '__nonExisting__',
                                                                              through_collection: 'passport'
                                                                            })
              end.to raise_error(ForestException, "Column not found: 'passport.__nonExisting__'")
            end

            it 'throws with a non existent fk' do
              expect do
                @datasource_decorator.get_collection('person').add_relation('person', {
                                                                              type: 'ManyToMany',
                                                                              foreign_collection: 'passport',
                                                                              foreign_key: '__nonExisting__',
                                                                              origin_key: 'owner_id',
                                                                              through_collection: 'passport'
                                                                            })
              end.to raise_error(ForestException, "Column not found: 'passport.__nonExisting__'")
            end
          end

          context 'when there is a given originKeyTarget that does not match the target type' do
            it 'throws' do
              expect do
                @datasource_decorator.get_collection('person').add_relation('person', {
                                                                              type: 'ManyToMany',
                                                                              foreign_collection: 'passport',
                                                                              foreign_key: 'owner_id',
                                                                              origin_key: 'owner_id',
                                                                              through_collection: 'passport',
                                                                              origin_key_target: 'name'
                                                                            })
              end.to raise_error(ForestException, "Types from 'passport.owner_id' and 'person.name' do not match.")
            end
          end

          context 'when there are a given originKeyTarget and foreignKeyTarget' do
            it 'registers the relation' do
              expect do
                @datasource_decorator.get_collection('person').add_relation('person', {
                                                                              type: 'ManyToMany',
                                                                              foreign_collection: 'passport',
                                                                              foreign_key: 'owner_id',
                                                                              origin_key: 'owner_id',
                                                                              through_collection: 'passport',
                                                                              origin_key_target: 'id',
                                                                              foreign_key_target: 'id'
                                                                            })
              end.not_to raise_error
            end
          end

          context 'when there are not a given originKeyTarget and foreignKeyTarget' do
            it 'registers the relation' do
              expect do
                @datasource_decorator.get_collection('person').add_relation('person', {
                                                                              type: 'ManyToMany',
                                                                              foreign_collection: 'passport',
                                                                              foreign_key: 'owner_id',
                                                                              origin_key: 'owner_id',
                                                                              through_collection: 'passport'
                                                                            })
              end.not_to raise_error
            end
          end
        end

        context 'when emulated projection' do
          it 'fetches fields from a many to one relation' do
            @datasource_decorator.get_collection('passport').add_relation('owner', {
                                                                            type: 'ManyToOne',
                                                                            foreign_collection: 'person',
                                                                            foreign_key: 'owner_id'
                                                                          })

            records = @datasource_decorator.get_collection('passport').list(
              caller,
              Filter.new,
              Projection.new(%w[id owner:name])
            )

            expect(records).to eq([
                                    { 'id' => 101, 'owner' => { 'name' => 'Mae S. Waldron' } },
                                    { 'id' => 102, 'owner' => { 'name' => 'Sharon J. Whalen' } },
                                    { 'id' => 103, 'owner' => nil }
                                  ])
          end

          it 'fetches fields from a one to one relation' do
            @datasource_decorator.get_collection('person').add_relation('passport', {
                                                                          type: 'OneToOne',
                                                                          foreign_collection: 'passport',
                                                                          origin_key: 'owner_id',
                                                                          origin_key_target: 'other_id'
                                                                        })

            records = @datasource_decorator.get_collection('person').list(
              caller,
              Filter.new,
              Projection.new(%w[id name passport:issue_date])
            )

            expect(records).to eq([
                                    { 'id' => 201, 'name' => 'Sharon J. Whalen', 'passport' => { 'issue_date' => '2017-01-01' } },
                                    { 'id' => 202, 'name' => 'Mae S. Waldron', 'passport' => { 'issue_date' => '2010-01-01' } },
                                    { 'id' => 203, 'name' => 'Joseph P. Rodriguez', 'passport' => nil }
                                  ])
          end

          it 'fetches fields from a one to many relation' do
            @datasource_decorator.get_collection('person').add_relation('passport', {
                                                                          type: 'OneToMany',
                                                                          foreign_collection: 'passport',
                                                                          origin_key: 'owner_id',
                                                                          origin_key_target: 'other_id'
                                                                        })

            records = @datasource_decorator.get_collection('person').list(
              caller,
              Filter.new,
              Projection.new(%w[id name passport:issue_date])
            )

            expect(records).to eq([
                                    { 'id' => 201, 'name' => 'Sharon J. Whalen', 'passport' => { 'issue_date' => '2017-01-01' } },
                                    { 'id' => 202, 'name' => 'Mae S. Waldron', 'passport' => { 'issue_date' => '2010-01-01' } },
                                    { 'id' => 203, 'name' => 'Joseph P. Rodriguez', 'passport' => nil }
                                  ])
          end

          it 'fetches fields from a many to many relation' do
            @datasource_decorator.get_collection('person').add_relation('persons', {
                                                                          type: 'ManyToMany',
                                                                          foreign_collection: 'person',
                                                                          foreign_key: 'owner_id',
                                                                          origin_key: 'owner_id',
                                                                          through_collection: 'passport',
                                                                          origin_key_target: 'other_id',
                                                                          foreign_key_target: 'id'
                                                                        })

            records = @datasource_decorator.get_collection('person').list(
              caller,
              Filter.new,
              Projection.new(%w[id name persons:name])
            )

            expect(records).to eq([
                                    { 'id' => 201, 'name' => 'Sharon J. Whalen', 'persons' => nil },
                                    { 'id' => 202, 'name' => 'Mae S. Waldron', 'persons' => nil },
                                    { 'id' => 203, 'name' => 'Joseph P. Rodriguez', 'persons' => nil }
                                  ])
          end

          it 'fetches fields from a native behind an emulated one' do
            @datasource_decorator.get_collection('person').add_relation('passport', {
                                                                          type: 'OneToOne',
                                                                          foreign_collection: 'passport',
                                                                          origin_key: 'owner_id'
                                                                        })
            @datasource_decorator.get_collection('passport').add_relation('owner', {
                                                                            type: 'ManyToOne',
                                                                            foreign_collection: 'person',
                                                                            foreign_key: 'owner_id'
                                                                          })

            records = @datasource_decorator.get_collection('person').list(
              caller,
              Filter.new,
              Projection.new(%w[id name passport:picture:filename])
            )

            expect(records).to eq([
                                    { 'id' => 201, 'name' => 'Sharon J. Whalen', 'passport' => { 'picture' => { 'filename' => 'pic2.jpg' } } },
                                    { 'id' => 202, 'name' => 'Mae S. Waldron', 'passport' => { 'picture' => { 'filename' => 'pic1.jpg' } } },
                                    { 'id' => 203, 'name' => 'Joseph P. Rodriguez', 'passport' => nil }
                                  ])
          end

          it 'does not break with deep reprojection' do
            @datasource_decorator.get_collection('person').add_relation('passport', {
                                                                          type: 'OneToOne',
                                                                          foreign_collection: 'passport',
                                                                          origin_key: 'owner_id'
                                                                        })
            @datasource_decorator.get_collection('passport').add_relation('owner', {
                                                                            type: 'ManyToOne',
                                                                            foreign_collection: 'person',
                                                                            foreign_key: 'owner_id'
                                                                          })

            records = @datasource_decorator.get_collection('person').list(
              caller,
              Filter.new,
              Projection.new(%w[id name passport:owner:passport:issue_date])
            )

            expect(records).to eq([
                                    { 'id' => 201, 'name' => 'Sharon J. Whalen', 'passport' => { 'owner' => { 'passport' => { 'issue_date' => '2017-01-01' } } } },
                                    { 'id' => 202, 'name' => 'Mae S. Waldron', 'passport' => { 'owner' => { 'passport' => { 'issue_date' => '2010-01-01' } } } },
                                    { 'id' => 203, 'name' => 'Joseph P. Rodriguez', 'passport' => nil }
                                  ])
          end

          context 'with two emulated relations' do
            before do
              @datasource_decorator.get_collection('person').add_relation('passport', {
                                                                            type: 'OneToOne',
                                                                            foreign_collection: 'passport',
                                                                            origin_key: 'owner_id'
                                                                          })
              @datasource_decorator.get_collection('passport').add_relation('owner', {
                                                                              type: 'ManyToOne',
                                                                              foreign_collection: 'person',
                                                                              foreign_key: 'owner_id'
                                                                            })
            end

            context 'when emulated filtering' do
              it 'filters by a many to one relation' do
                records = @datasource_decorator.get_collection('passport').list(
                  caller,
                  Filter.new(condition_tree: Nodes::ConditionTreeLeaf.new('owner:name', 'Equal', 'Mae S. Waldron')),
                  Projection.new(%w[id issue_date])
                )

                expect(records).to eq([{ 'id' => 101, 'issue_date' => '2010-01-01' }])
              end

              it 'filters by a one to one relation' do
                records = @datasource_decorator.get_collection('person').list(
                  caller,
                  Filter.new(condition_tree: Nodes::ConditionTreeLeaf.new('passport:issue_date', 'Equal', '2017-01-01')),
                  Projection.new(%w[id name])
                )

                expect(records).to eq([{ 'id' => 201, 'name' => 'Sharon J. Whalen' }])
              end

              it 'filters by native relation behind an emulated one' do
                records = @datasource_decorator.get_collection('person').list(
                  caller,
                  Filter.new(condition_tree: Nodes::ConditionTreeLeaf.new('passport:picture:filename', 'Equal', 'pic1.jpg')),
                  Projection.new(%w[id name])
                )

                expect(records).to eq([{ 'id' => 202, 'name' => 'Mae S. Waldron' }])
              end

              it 'does not break with deep filters' do
                records = @datasource_decorator.get_collection('person').list(
                  caller,
                  Filter.new(condition_tree: Nodes::ConditionTreeLeaf.new('passport:owner:passport:issue_date', 'Equal', '2017-01-01')),
                  Projection.new(%w[id name])
                )

                expect(records).to eq([{ 'id' => 201, 'name' => 'Sharon J. Whalen' }])
              end
            end

            context 'when emulated sorting' do
              it 'replaces sorts in emulated many to one into sort by fk' do
                ascending = @datasource_decorator.get_collection('passport').list(
                  caller,
                  Filter.new(sort: ForestAdminDatasourceToolkit::Components::Query::Sort.new([{ field: 'owner:name', ascending: true }])),
                  Projection.new(%w[id owner_id owner:name])
                )

                descending = @datasource_decorator.get_collection('passport').list(
                  caller,
                  Filter.new(sort: ForestAdminDatasourceToolkit::Components::Query::Sort.new([{ field: 'owner:name', ascending: false }])),
                  Projection.new(%w[id owner_id owner:name])
                )

                expect(ascending).to eq([
                                          { 'id' => 103, 'owner_id' => nil, 'owner' => nil },
                                          { 'id' => 102, 'owner_id' => 201, 'owner' => { 'name' => 'Sharon J. Whalen' } },
                                          { 'id' => 101, 'owner_id' => 202, 'owner' => { 'name' => 'Mae S. Waldron' } }
                                        ])

                expect(descending).to eq([
                                           { 'id' => 101, 'owner_id' => 202, 'owner' => { 'name' => 'Mae S. Waldron' } },
                                           { 'id' => 102, 'owner_id' => 201, 'owner' => { 'name' => 'Sharon J. Whalen' } },
                                           { 'id' => 103, 'owner_id' => nil, 'owner' => nil }
                                         ])
              end
            end

            context 'when emulated aggregation' do
              it "does not emulate aggregation which don't need it" do
                filter = Filter.new
                aggregation = Aggregation.new(operation: 'Count', groups: [{ field: 'name' }])
                groups = @datasource_decorator.get_collection('person').aggregate(caller, filter, aggregation)

                expect(groups).to eq([
                                       { value: 1, group: { 'name' => 'Sharon J. Whalen' } },
                                       { value: 1, group: { 'name' => 'Mae S. Waldron' } },
                                       { value: 1, group: { 'name' => 'Joseph P. Rodriguez' } }
                                     ])
              end

              it 'gives valid results otherwise' do
                filter = Filter.new
                aggregation = Aggregation.new(operation: 'Count', groups: [{ field: 'passport:picture:filename' }])
                groups = @datasource_decorator.get_collection('person').aggregate(caller, filter, aggregation, 2)

                expect(groups).to eq([
                                       { value: 1, group: { 'passport:picture:filename' => 'pic2.jpg' } },
                                       { value: 1, group: { 'passport:picture:filename' => 'pic1.jpg' } }
                                     ])
              end
            end
          end
        end
      end
    end
  end
end
