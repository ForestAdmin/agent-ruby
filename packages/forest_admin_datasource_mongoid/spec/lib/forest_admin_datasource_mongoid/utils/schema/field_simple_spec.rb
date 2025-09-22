require 'spec_helper'

module ForestAdminDatasourceMongoid
  module Utils
    module Schema
      # rubocop:disable Lint/ConstantDefinitionInBlock
      # rubocop:disable RSpec/LeakyConstantDeclaration
      describe FieldsGenerator do
        let(:stack) { [{ prefix: nil, as_fields: [], as_models: [] }] }

        describe 'when field is required' do
          let(:model) do
            Class.new do
              include Mongoid::Document
              field :a_field, type: Integer
              validates :a_field, presence: true
            end
          end

          it 'builds the validation with present operator' do
            fields_schema = described_class.build_fields_schema(model, stack)

            expect(fields_schema['a_field'].validations).to eq [{ operator: 'present' }]
          end
        end

        describe 'when field is not required' do
          let(:model) do
            Class.new do
              include Mongoid::Document
              field :a_field, type: Integer
            end
          end

          it 'does not add a validation' do
            fields_schema = described_class.build_fields_schema(model, stack)

            expect(fields_schema['a_field'].validations).to be_empty
          end
        end

        describe 'when field has a default value' do
          let(:model) do
            Class.new do
              include Mongoid::Document
              field :a_field, type: String, default: 'default_value'
            end
          end

          it 'builds the field schema with a default value' do
            fields_schema = described_class.build_fields_schema(model, stack)

            expect(fields_schema['a_field'].default_value).to eq('default_value')
          end
        end

        describe 'when field is the primary key' do
          it 'builds the field schema with a primary key as true' do
            fields_schema = described_class.build_fields_schema(Post, stack)

            expect(fields_schema['_id'].is_primary_key).to be(true)
          end
        end

        describe 'when field is immutable' do
          it 'builds the field schema with is_read_only as true' do
            class ImmutableFieldModel
              include Mongoid::Document
              field :a_field, type: Date
              attr_readonly :a_field
            end

            model = ImmutableFieldModel.new(a_field: Date.today)
            model.save!

            model.a_field = Date.tomorrow
            expect(model.changed?).to be(false)
            expect(model.a_field).to eq(Date.today)
          end
        end

        describe 'when the enum is not an array of strings' do
          let(:model) do
            Class.new do
              include Mongoid::Document
              field :a_field, type: Integer
              validates :a_field, inclusion: { in: [1, 2] }
            end
          end

          it 'raises an error' do
            fields_schema = described_class.build_fields_schema(model, stack)

            expect(fields_schema['a_field'].column_type).to eq('Number')
          end
        end

        describe 'with array fields' do
          describe 'with primitive array' do
            let(:model) do
              Class.new do
                include Mongoid::Document
                field :a_field, type: Array
              end
            end

            it 'builds the right column type' do
              fields_schema = described_class.build_fields_schema(model, stack)

              expect(fields_schema['a_field'].column_type).to eq('Json')
            end
          end

          describe 'with object array' do
            it 'builds the right schema' do
              class ObjectArrayModel
                include Mongoid::Document
                embeds_many :nested_objects, class_name: 'NestedObject'
              end

              class NestedObject
                include Mongoid::Document
                field :level, type: Integer
              end

              fields_schema = described_class.build_fields_schema(ObjectArrayModel, stack)

              expect(fields_schema['nested_objects'].column_type).to eq([{ 'level' => 'Number' }])
            end
          end
        end

        describe 'with an objectId and a ref' do
          it 'adds a relation _manyToOne in the fields schema' do
            class ManyToOneModel
              include Mongoid::Document
              belongs_to :company, class_name: 'Company'
            end

            class Company
              include Mongoid::Document
              field :name, type: String
            end

            fields_schema = described_class.build_fields_schema(ManyToOneModel, stack)

            expect(fields_schema['company_id__many_to_one']).to be_a(ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema)
            expect(fields_schema['company_id__many_to_one'].foreign_collection).to eq('ForestAdminDatasourceMongoid__Utils__Schema__Company')
            expect(fields_schema['company_id__many_to_one'].foreign_key).to eq('company_id')
            expect(fields_schema['company_id__many_to_one'].type).to eq('ManyToOne')
            expect(fields_schema['company_id__many_to_one'].foreign_key_target).to eq('_id')
          end
        end
      end
      # rubocop:enable Lint/ConstantDefinitionInBlock
      # rubocop:enable RSpec/LeakyConstantDeclaration
    end
  end
end
