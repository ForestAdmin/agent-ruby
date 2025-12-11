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

          describe 'form_value (alias)' do
            it 'works as an alias for get_form_value' do
              context = described_class.new(@collection, caller, { 'title' => 'Foundation' }, Filter.new)
              expect(context.form_value('title')).to eq('Foundation')
            end

            it 'return null value when a key doesn\'t exist' do
              context = described_class.new(@collection, caller, { 'title' => 'Foundation' }, Filter.new)
              expect(context.form_value('foo')).to be_nil
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

          describe 'attribute access pattern' do
            let(:form_values) { { 'title' => 'Foundation', 'year' => 1951 } }
            let(:filter) { Filter.new }
            let(:context) { described_class.new(@collection, caller, form_values, filter) }

            describe 'getter methods' do
              it 'provides read access to filter' do
                expect(context.filter).to eq(filter)
              end

              it 'provides read access to form_values' do
                expect(context.form_values).to eq(form_values)
              end

              it 'provides read access to used' do
                expect(context.used).to eq([])
              end
            end

            describe 'standard setter methods (without underscore)' do
              it 'does not expose filter= setter' do
                expect(context).not_to respond_to(:filter=)
              end

              it 'does not expose form_values= setter' do
                expect(context).not_to respond_to(:form_values=)
              end

              it 'does not expose used= setter' do
                expect(context).not_to respond_to(:used=)
              end

              it 'raises NoMethodError when attempting standard setters' do
                expect { context.filter = Filter.new }.to raise_error(NoMethodError, /filter=/)
                expect { context.form_values = {} }.to raise_error(NoMethodError, /form_values=/)
                expect { context.used = [] }.to raise_error(NoMethodError, /used=/)
              end
            end

            describe 'underscore-prefixed setter methods (advanced use)' do
              it 'exposes _filter= for cautious modification' do
                expect(context).to respond_to(:_filter=)
              end

              it 'exposes _form_values= for cautious modification' do
                expect(context).to respond_to(:_form_values=)
              end

              it 'exposes _used= for cautious modification' do
                expect(context).to respond_to(:_used=)
              end

              it 'allows modifying filter with _filter=' do
                new_filter = Filter.new
                context._filter = new_filter
                expect(context.filter).to eq(new_filter)
              end

              it 'allows modifying form_values with _form_values=' do
                new_values = { 'title' => 'Modified' }
                context._form_values = new_values
                expect(context.form_values).to eq(new_values)
              end

              it 'allows modifying used array with _used=' do
                new_used = %w[field1 field2]
                context._used = new_used
                expect(context.used).to eq(new_used)
              end
            end

            describe 'design pattern validation' do
              it 'enforces read-by-default, write-with-caution pattern' do
                # Getters are always available (safe)
                expect(context).to respond_to(:filter)
                expect(context).to respond_to(:form_values)
                expect(context).to respond_to(:used)

                # Standard setters don't exist (prevents accidental mutation)
                expect(context).not_to respond_to(:filter=)
                expect(context).not_to respond_to(:form_values=)
                expect(context).not_to respond_to(:used=)

                # Underscore setters exist (signals advanced/cautious use)
                expect(context).to respond_to(:_filter=)
                expect(context).to respond_to(:_form_values=)
                expect(context).to respond_to(:_used=)
              end
            end
          end
        end
      end
    end
  end
end
