require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Action
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Decorators
      include ForestAdminDatasourceToolkit::Schema
      include ForestAdminDatasourceToolkit::Components::Query

      describe ActionCollectionDecorator do
        include_context 'with caller'

        before do
          datasource = Datasource.new
          @collection_book = build_collection(
            name: 'book',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'author_id' => ColumnSchema.new(column_type: 'String'),
                'author' => Relations::ManyToOneSchema.new(
                  foreign_key: 'author_id',
                  foreign_collection: 'person',
                  foreign_key_target: 'id'
                ),
                'title' => ColumnSchema.new(column_type: 'String')
              }
            },
            execute: nil,
            get_form: nil
          )

          @collection_person = build_collection(
            name: 'person',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'first_name' => ColumnSchema.new(column_type: 'String'),
                'last_name' => ColumnSchema.new(column_type: 'String'),
                'book' => Relations::OneToOneSchema.new(
                  origin_key: 'author_id',
                  origin_key_target: 'id',
                  foreign_collection: 'book'
                )
              }
            }
          )

          datasource.add_collection(@collection_book)
          datasource.add_collection(@collection_person)

          datasource_decorator = DatasourceDecorator.new(datasource, described_class)

          @decorated_book = datasource_decorator.get_collection('book')
          @decorated_person = datasource_decorator.get_collection('person')
        end

        describe 'without actions' do
          it 'delegate execute calls' do
            @decorated_book.execute(caller, 'someAction', { firstname: 'John' }, Filter.new)
            expect(@collection_book).to have_received(:execute)
          end

          it 'delegate ger_form calls' do
            @decorated_book.get_form(
              caller,
              'someAction',
              { firstname: 'John' },
              Filter.new,
              { changedField: 'a field' }
            )
            expect(@collection_book).to have_received(:get_form)
          end
        end

        describe 'with a bulk action with no form and void result' do
          before do
            @decorated_book.add_action(
              'make photocopy',
              BaseAction.new(scope: Types::ActionScope::BULK) { nil }
            )
          end

          it 'be flagged as static form' do
            expect(@decorated_book.schema[:actions]['make photocopy'].static_form).to be(true)
          end

          it 'execute and return default response' do
            result = @decorated_book.execute(caller, 'make photocopy', {}, Filter.new)
            expect(result).to eq({ headers: {}, type: 'Success', success: 'Success', refresh: { relationships: [] }, html: nil })
          end

          it 'generate empty form' do
            form = @decorated_book.get_form(caller, 'make photocopy', {}, Filter.new)
            expect(form).to eq([])
          end
        end

        describe 'with a global action with a static form' do
          before do
            @decorated_book.add_action(
              'make photocopy',
              BaseAction.new(
                scope: Types::ActionScope::GLOBAL,
                form: [
                  { label: 'firstname', type: Types::FieldType::STRING },
                  { label: 'lastname', type: Types::FieldType::STRING }
                ]
              ) { |_context, result_builder| result_builder.error(message: 'meeh') }
            )
          end

          it 'be flagged as static form' do
            expect(@decorated_book.schema[:actions]['make photocopy'].static_form).to be(true)
          end

          it 'generate form' do
            form = @decorated_book.get_form(caller, 'make photocopy', {}, Filter.new)

            expect(form).to include(
              have_attributes(label: 'firstname', type: 'String'),
              have_attributes(label: 'lastname', type: 'String')
            )
          end
        end

        describe 'with a single action with a if_conditions' do
          context 'with row element' do
            before do
              @decorated_book.add_action(
                'make photocopy',
                BaseAction.new(
                  scope: Types::ActionScope::GLOBAL,
                  form: [
                    { label: 'noIf', type: Types::FieldType::STRING },
                    {
                      label: 'dynamicIfFalse',
                      type: Types::FieldType::STRING,
                      if_condition: proc { false }
                    },
                    {
                      label: 'dynamicIfTrue',
                      type: Types::FieldType::STRING,
                      if_condition: proc { true }
                    },
                    {
                      type: 'Layout',
                      component: 'Row',
                      fields: [
                        {
                          type: Types::FieldType::STRING,
                          label: 'sub_field_1',
                          if_condition: proc { false }
                        },
                        {
                          type: Types::FieldType::STRING,
                          label: 'sub_field_2',
                          if_condition: proc { true }
                        }
                      ]
                    },
                    {
                      type: 'Layout',
                      component: 'Row',
                      fields: [
                        {
                          type: Types::FieldType::STRING,
                          label: 'sub_field_3',
                          if_condition: proc { false }
                        }
                      ]
                    }
                  ]
                ) { |_context, result_builder| result_builder.error(message: 'meeh') }
              )
            end

            it 'drop ifs which are false if required' do
              form = @decorated_book.get_form(caller, 'make photocopy', {}, Filter.new, { include_hidden_fields: false })

              expect(form).to include(
                have_attributes(label: 'noIf', type: 'String'),
                have_attributes(label: 'dynamicIfTrue', type: 'String')
              )
            end

            it 'drop row element if fields are empty and remove field not required in row' do
              form = @decorated_book.get_form(caller, 'make photocopy', {}, Filter.new, { include_hidden_fields: false })

              expect(form.size).to eq(3)
              expect(form.last.fields).to include(
                have_attributes(label: 'sub_field_2', type: 'String')
              )
            end

            it 'not dropIfs if required' do
              form = @decorated_book.get_form(caller, 'make photocopy', {}, Filter.new, { include_hidden_fields: true })

              expect(form).to include(
                have_attributes(label: 'noIf', type: 'String'),
                have_attributes(label: 'dynamicIfFalse', type: 'String'),
                have_attributes(label: 'dynamicIfTrue', type: 'String')
              )
            end
          end

          context 'with page element' do
            before do
              @decorated_book.add_action(
                'make photocopy',
                BaseAction.new(
                  scope: Types::ActionScope::GLOBAL,
                  form: [
                    {
                      type: 'Layout',
                      component: 'Page',
                      elements: [
                        { label: 'field_1', type: Types::FieldType::STRING, if_condition: proc { false } }
                      ]
                    },
                    {
                      type: 'Layout',
                      component: 'Page',
                      elements: [
                        { label: 'field_2', type: Types::FieldType::STRING, if_condition: proc { true } }
                      ]
                    }
                  ]
                ) { |_context, result_builder| result_builder.error(message: 'meeh') }
              )
            end

            it 'drop page if element are empty' do
              form = @decorated_book.get_form(caller, 'make photocopy', {}, Filter.new, { include_hidden_fields: false })

              expect(form.size).to eq(1)
              expect(form.first.elements).to include(
                have_attributes(label: 'field_2', type: 'String')
              )
            end
          end
        end

        describe 'with a single action with default values' do
          before do
            @decorated_book.add_action(
              'make photocopy',
              BaseAction.new(
                scope: Types::ActionScope::GLOBAL,
                form: [
                  {
                    type: 'Layout',
                    component: 'Page',
                    elements: [
                      { label: 'field_1', type: Types::FieldType::STRING, default_value: proc { 'default value field_1' } },
                      {
                        type: 'Layout',
                        component: 'Row',
                        fields: [
                          {
                            type: Types::FieldType::STRING,
                            label: 'sub_field_1',
                            default_value: proc { 'default value sub_field_1' }
                          }
                        ]
                      }
                    ]
                  }
                ]
              ) { |_context, result_builder| result_builder.error(message: 'meeh') }
            )
          end

          it 'drop all default values' do
            form = @decorated_book.get_form(caller, 'make photocopy', {}, Filter.new, { include_hidden_fields: false })

            expect(form).to include(
              have_attributes(
                type: 'Layout',
                component: 'Page',
                elements: include(
                  have_attributes(label: 'field_1', type: 'String', value: 'default value field_1'),
                  have_attributes(
                    type: 'Layout',
                    component: 'Row',
                    fields: include(have_attributes(label: 'sub_field_1', type: 'String', value: 'default value sub_field_1'))
                  )
                )
              )
            )
          end
        end

        describe 'with single action with both load and change hooks' do
          before do
            @decorated_book.add_action(
              'make photocopy',
              BaseAction.new(
                scope: Types::ActionScope::GLOBAL,
                form: [
                  {
                    label: 'firstname',
                    type: Types::FieldType::STRING,
                    default_value: proc { 'DynamicDefault' }
                  },
                  {
                    label: 'lastname',
                    type: Types::FieldType::STRING,
                    is_read_only: proc { |context| !context.get_form_value('firstname').nil? }
                  }
                ]
              ) { |_context, result_builder| result_builder.error(message: 'meeh') }
            )
          end

          it 'be flagged as dynamic form' do
            expect(@decorated_book.schema[:actions]['make photocopy'].static_form).to be(false)
          end

          it 'compute dynamic default value (no data == load hook)' do
            form = @decorated_book.get_form(caller, 'make photocopy', {}, Filter.new)

            expect(form).to include(
              have_attributes(label: 'firstname', value: 'DynamicDefault', watch_changes: true),
              have_attributes(label: 'lastname', is_read_only: true, watch_changes: false)
            )
          end

          it 'compute dynamic default value on added field' do
            form = @decorated_book.get_form(caller, 'make photocopy', { 'lastname' => 'value' }, Filter.new)

            expect(form).to include(
              have_attributes(label: 'firstname', value: 'DynamicDefault', watch_changes: true),
              have_attributes(label: 'lastname', value: 'value', is_read_only: true, watch_changes: false)
            )
          end

          it 'compute readonly (false) and keep null firstname' do
            form = @decorated_book.get_form(caller, 'make photocopy', { 'firstname' => nil }, Filter.new)

            expect(form).to include(
              have_attributes(label: 'firstname', value: nil, watch_changes: true),
              have_attributes(label: 'lastname', is_read_only: false, watch_changes: false)
            )
          end

          it 'compute readonly (true) and keep "John" firstname' do
            form = @decorated_book.get_form(caller, 'make photocopy', { 'firstname' => 'John' }, Filter.new)

            expect(form).to include(
              have_attributes(label: 'firstname', value: 'John', watch_changes: true),
              have_attributes(label: 'lastname', is_read_only: true, watch_changes: false)
            )
          end
        end

        describe 'field_changed?' do
          before do
            @decorated_book.add_action(
              'make photocopy',
              BaseAction.new(
                scope: Types::ActionScope::GLOBAL,
                form: [
                  {
                    label: 'change',
                    type: Types::FieldType::STRING,
                    default_value: proc { 'DynamicDefault' }
                  },
                  {
                    label: 'to change',
                    type: Types::FieldType::STRING,
                    is_read_only: true,
                    value: proc do |context|
                      context.get_form_value('change') if context.field_changed?('change')
                    end
                  },
                  {
                    type: 'Layout',
                    component: 'Row',
                    fields: [
                      {
                        type: Types::FieldType::STRING,
                        label: 'sub_field_change',
                        is_required: true
                      },
                      DynamicField.new(
                        type: Types::FieldType::STRING,
                        label: 'sub_field_to_change',
                        is_read_only: true,
                        value: proc do |context|
                          context.get_form_value('sub_field_change') if context.field_changed?('sub_field_change')
                        end
                      )
                    ]
                  }
                ]
              ) { |_context, result_builder| result_builder.error(message: 'meeh') }
            )
          end

          it 'add watchChange property to fields that need to trigger a recompute on change' do
            form = @decorated_book.get_form(caller, 'make photocopy', {}, Filter.new)

            expect(form).to include(
              have_attributes(label: 'change', watch_changes: true),
              have_attributes(label: 'to change', is_read_only: true, watch_changes: false)
            )
          end

          it 'add watchChange property to sub fields of row layout that need to trigger a recompute on change' do
            form = @decorated_book.get_form(caller, 'make photocopy', {}, Filter.new)

            expect(form.last.fields).to include(
              have_attributes(label: 'sub_field_change', watch_changes: true),
              have_attributes(label: 'sub_field_to_change', is_read_only: true, watch_changes: false)
            )
          end
        end

        describe 'with single action with search hook' do
          before do
            @decorated_book.add_action(
              'make photocopy',
              BaseAction.new(
                scope: Types::ActionScope::GLOBAL,
                form: [
                  { label: 'firstname', type: Types::FieldType::STRING, default_value: proc { 'DynamicDefault' } },
                  {
                    label: 'lastname',
                    type: Types::FieldType::STRING,
                    is_read_only: proc { |context| !context.form_value('firstname').nil? }
                  }
                ]
              ) { |_context, result_builder| result_builder.error(message: 'meeh') }
            )
          end

          it 'only return the field matching the searchField' do
            fields = @decorated_book.get_form(
              caller,
              'make photocopy',
              {},
              Filter.new,
              {
                changed_field: 'toto',
                search_field: 'firstname',
                search_values: { firstname: 'first' }
              }
            )

            expect(fields).to include(
              have_attributes(
                label: 'firstname',
                type: 'String',
                value: 'DynamicDefault',
                watch_changes: false
              )
            )
          end
        end

        describe 'add_action' do
          it 'raise an error if multiple fields with same id are provided' do
            action = BaseAction.new(
              scope: Types::ActionScope::GLOBAL,
              form: [
                { id: 'id', label: 'amount', type: Types::FieldType::NUMBER },
                { id: 'id', label: 'cost', type: Types::FieldType::NUMBER }
              ]
            ) { |_context, result_builder| result_builder.error(message: 'foo') }

            expect do
              @decorated_book.add_action('make photocopy', action)
            end.to raise_error(Exceptions::ConflictError, "All field must have different 'id'. Conflict come from field 'id'")
          end

          it 'raise an error if multiple fields with same id are provided in row' do
            action = BaseAction.new(
              scope: Types::ActionScope::GLOBAL,
              form: [
                {
                  type: 'Layout',
                  component: 'Row',
                  fields: [
                    { id: 'id', label: 'amount', type: Types::FieldType::NUMBER },
                    { id: 'id', label: 'cost', type: Types::FieldType::NUMBER }
                  ]
                }
              ]
            ) { |_context, result_builder| result_builder.error(message: 'foo') }

            expect do
              @decorated_book.add_action('make photocopy', action)
            end.to raise_error(Exceptions::ConflictError, "All field must have different 'id'. Conflict come from field 'id'")
          end

          it 'raise an error if field (hash) is provided without id and label' do
            action = BaseAction.new(
              scope: Types::ActionScope::GLOBAL,
              form: [
                { type: Types::FieldType::NUMBER }
              ]
            ) { |_context, result_builder| result_builder.error(message: 'foo') }

            expect do
              @decorated_book.add_action('make photocopy', action)
            end.to raise_error(Exceptions::BadRequestError, "A field must have an 'id' or a 'label' defined.")
          end

          it 'raise an error if form mix form elements and pages' do
            action = BaseAction.new(
              scope: Types::ActionScope::GLOBAL,
              form: [
                { label: 'amount', type: Types::FieldType::NUMBER },
                {
                  type: 'Layout',
                  component: 'Page',
                  elements: [
                    { type: 'Layout', component: 'HtmlBlock', content: 'foo' }
                  ]
                }
              ]
            ) { |_context, result_builder| result_builder.error(message: 'foo') }

            expect do
              @decorated_book.add_action('make photocopy', action)
            end.to raise_error(Exceptions::BadRequestError, "You cannot mix pages and other form elements in smart action 'make photocopy' form")
          end
        end
      end
    end
  end
end
