require 'spec_helper'

module ForestAdminDatasourceMongoid
  module Utils
    module Schema
      describe FieldsGenerator do
        let(:stack) { [{ prefix: nil, as_fields: [], as_models: [] }] }

        describe 'Construction' do
          it 'does not modify the schema' do
            fields = described_class.build_fields_schema(Post, stack)
            expect(fields.keys).to eq(%w[_id created_at updated_at title body rating tag_ids])
          end

          it 'skips flattened models' do
            stack = [{ prefix: nil, as_fields: ['section.body'], as_models: ['section'] }]
            fields = described_class.build_fields_schema(Label, stack)

            expect(fields.keys).to eq(['_id', 'name', 'section@@@body'])
          end

          it 'flattens all nested fields when no level is provided' do
            stack = [{ prefix: nil, as_fields: ['section.content', 'section.body'], as_models: [] }]
            fields = described_class.build_fields_schema(Label, stack)

            expect(fields.keys).to eq(['_id', 'name', 'section@@@content', 'section@@@body'])
          end

          it 'flattens only requested fields' do
            stack = [{ prefix: nil, as_fields: ['label.name'], as_models: [] }]
            fields = described_class.build_fields_schema(Band, stack)

            expect(fields.keys).to eq(['_id', 'created_at', 'updated_at', 'label', 'label@@@name'])
          end

          it 'onlies flatten selected fields when level = 1' do
            stack = [{ prefix: nil, as_fields: ['label.name', 'label.section'], as_models: [] }]
            fields = described_class.build_fields_schema(Band, stack)

            expect(fields.keys).to eq(['_id', 'created_at', 'updated_at', 'label@@@name', 'label@@@section'])
          end

          it 'returns a "String" as type when "_id" is generated' do
            fields = described_class.build_fields_schema(Post, stack)

            expect(fields['_id'].column_type).to eq('String')
          end
        end
      end
    end
  end
end
