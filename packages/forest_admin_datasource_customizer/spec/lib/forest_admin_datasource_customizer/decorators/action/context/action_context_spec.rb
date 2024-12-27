require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Action
      module Context
        include ForestAdminDatasourceToolkit
        include ForestAdminDatasourceToolkit::Decorators
        include ForestAdminDatasourceToolkit::Schema
        include ForestAdminDatasourceToolkit::Components::Query
        describe ActionContext do
          include_context 'with caller'
          before do
            datasource = Datasource.new
            collection = Collection.new(datasource, 'book')
            collection.add_fields(
              {
                'id' => ColumnSchema.new(column_type: Concerns::PrimitiveTypes::NUMBER, is_primary_key: true),
                'title' => ColumnSchema.new(column_type: Concerns::PrimitiveTypes::STRING)
              }
            )
            datasource.add_collection(collection)
            datasource_decorator = DatasourceDecorator.new(datasource, ActionCollectionDecorator)

            @collection = datasource_decorator.get_collection('book')
            allow(@collection).to receive(:list).and_return(
              [
                { 'id' => 1, 'title' => 'Foundation' },
                { 'id' => 2, 'title' => 'Beat the dealer' }
              ]
            )
          end

          describe 'get_form_value' do
            it 'return the correct value when a key is defined' do
              context = described_class.new(@collection, caller, { 'title' => 'Foundation' }, Filter.new)
              expect(context.get_form_value('title')).to eq('Foundation')
            end

            it 'return null value when a key doesn\'t exist' do
              context = described_class.new(@collection, caller, { 'title' => 'Foundation' }, Filter.new)
              expect(context.get_form_value('foo')).to be_nil
            end
          end

          describe 'get_records' do
            it 'return the correct values of the list collection' do
              context = described_class.new(@collection, caller, { 'title' => 'Foundation' }, Filter.new)
              expect(context.get_records(%w[id title])).to eq(
                [
                  { 'id' => 1, 'title' => 'Foundation' },
                  { 'id' => 2, 'title' => 'Beat the dealer' }
                ]
              )
            end
          end

          describe 'record_ids' do
            it 'return the pk list' do
              context = described_class.new(@collection, caller, { 'title' => 'Foundation' }, Filter.new)
              expect(context.record_ids).to eq([1, 2])
            end
          end

          describe 'field_changed?' do
            it 'add watchChange property to fields that need to trigger a recompute on change' do
              @collection.add_action(
                'make photocopy',
                BaseAction.new(
                  scope: Types::ActionScope::SINGLE,
                  form: [
                    { label: 'change', type: Types::FieldType::STRING },
                    {
                      label: 'to change',
                      type: Types::FieldType::STRING,
                      is_read_only: true,
                      value: proc do |context|
                        return context.get_form_value('change') if context.field_changed?('change')
                      end
                    }
                  ]
                ) do |_context, result_builder|
                  result_builder.success(message: 'Foo!')
                end
              )
              fields = @collection.get_form(caller, 'make photocopy')

              expect(fields[0].watch_changes?).to be(true)
              expect(fields[1].watch_changes?).to be(false)
            end
          end
        end
      end
    end
  end
end
