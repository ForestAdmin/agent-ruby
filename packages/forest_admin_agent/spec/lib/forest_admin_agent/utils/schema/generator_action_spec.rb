require 'spec_helper'

module ForestAdminAgent
  module Utils
    module Schema
      include ForestAdminDatasourceToolkit::Components::Actions
      include ForestAdminDatasourceCustomizer::Decorators::Action

      describe GeneratorAction do
        describe 'without form' do
          before do
            @collection = collection_build(
              schema: {
                actions: {
                  'Send email' => BaseAction.new(scope: Types::ActionScope::SINGLE)
                }
              }
            )
          end

          it 'generate schema correctly' do
            schema = described_class.build_schema(@collection, 'Send email')

            expect(schema).to eq(
              {
                id: 'collection-0-send-email',
                name: 'Send email',
                submitButtonLabel: nil,
                description: nil,
                type: 'single',
                baseUrl: nil,
                endpoint: '/forest/_actions/collection/0/send-email',
                httpMethod: 'POST',
                redirect: nil,
                download: false,
                fields: [],
                hooks: { load: false, change: ['changeHook'] }
              }
            )
          end
        end

        describe 'with no hooks' do
          before do
            @collection = collection_build(
              schema: {
                actions: {
                  'Send email' => BaseAction.new(
                    scope: Types::ActionScope::SINGLE
                  )
                }
              },
              get_form: [
                ActionField.new(
                  id: 'label',
                  label: 'label',
                  description: 'email',
                  type: 'String',
                  is_required: true,
                  is_read_only: false,
                  value: ''
                )
              ]
            )
          end

          it 'generate schema correctly' do
            schema = described_class.build_schema(@collection, 'Send email')

            expect(schema).to eq(
              {
                id: 'collection-0-send-email',
                name: 'Send email',
                submitButtonLabel: nil,
                description: nil,
                type: 'single',
                baseUrl: nil,
                endpoint: '/forest/_actions/collection/0/send-email',
                httpMethod: 'POST',
                redirect: nil,
                download: false,
                fields: [{
                  description: 'email',
                  isRequired: true,
                  isReadOnly: false,
                  field: 'label',
                  widgetEdit: nil,
                  type: 'String',
                  defaultValue: '',
                  label: 'label'
                }],
                hooks: { load: false, change: ['changeHook'] }
              }
            )
          end
        end

        describe 'with change hooks' do
          before do
            @collection = collection_build(
              schema: {
                actions: {
                  'Send email' => instance_double(
                    BaseAction,
                    {
                      scope: Types::ActionScope::SINGLE,
                      static_form?: true,
                      is_generate_file: false,
                      description: nil,
                      submit_button_label: nil
                    }
                  )
                }
              },
              get_form: [
                ActionField.new(
                  label: 'label',
                  description: 'email',
                  type: 'String',
                  is_required: true,
                  is_read_only: false,
                  value: '',
                  watch_changes: true
                )
              ]
            )
          end

          it 'generate schema correctly' do
            schema = described_class.build_schema(@collection, 'Send email')

            expect(schema[:fields][0][:hook]).to eq('changeHook')
          end
        end

        describe 'with widget' do
          it 'set the value null to widgetEdit if no widget is specified' do
            collection = collection_build(
              schema: {
                actions: {
                  'Send email' => instance_double(
                    BaseAction,
                    {
                      scope: Types::ActionScope::SINGLE,
                      static_form?: true,
                      is_generate_file: false,
                      description: nil,
                      submit_button_label: nil
                    }
                  )
                }
              },
              get_form: [
                ActionField.new(
                  label: 'label',
                  description: 'email',
                  type: 'String',
                  is_required: true,
                  is_read_only: false,
                  value: '',
                  watch_changes: false
                )
              ]
            )
            schema = described_class.build_schema(collection, 'Send email')

            expect(schema[:fields][0][:widgetEdit]).to be_nil
          end

          it 'generate the right configuration for dropdowns' do
            collection = collection_build(
              schema: {
                actions: {
                  'Send email' => instance_double(
                    BaseAction,
                    {
                      scope: Types::ActionScope::SINGLE,
                      static_form?: true,
                      is_generate_file: false,
                      description: nil,
                      submit_button_label: nil
                    }
                  )
                }
              },
              get_form: [
                ForestAdminDatasourceToolkit::Components::Actions::WidgetField::DropdownField.new(
                  label: 'label',
                  description: 'email',
                  type: 'String',
                  is_required: true,
                  is_read_only: false,
                  value: '',
                  watch_changes: false,
                  search: 'static',
                  options: [
                    { label: 'Paperback', value: '1' },
                    { label: 'Hardcover', value: '2' }
                  ]
                )
              ]
            )
            schema = described_class.build_schema(collection, 'Send email')

            expect(schema[:fields][0][:widgetEdit]).to eq(
              {
                name: 'dropdown',
                parameters: {
                  searchType: nil,
                  isSearchable: true,
                  placeholder: nil,
                  static: {
                    options: [
                      { label: 'Paperback', value: '1' },
                      { label: 'Hardcover', value: '2' }
                    ]
                  }
                }
              }
            )
          end
        end

        describe 'build_schema with layout element' do
          context 'with separator element' do
            before do
              @collection = collection_build(
                schema: {
                  actions: {
                    'Send email' => BaseAction.new(
                      scope: Types::ActionScope::SINGLE
                    )
                  }
                },
                get_form: [
                  ActionField.new(id: 'label', label: 'label', type: 'String'),
                  ActionLayoutElement::SeparatorElement.new
                ]
              )
            end

            it 'generate schema correctly' do
              schema = described_class.build_schema(@collection, 'Send email')

              expect(schema).to eq(
                {
                  id: 'collection-0-send-email',
                  name: 'Send email',
                  submitButtonLabel: nil,
                  description: nil,
                  type: 'single',
                  baseUrl: nil,
                  endpoint: '/forest/_actions/collection/0/send-email',
                  httpMethod: 'POST',
                  redirect: nil,
                  download: false,
                  fields: [
                    {
                      defaultValue: nil,
                      description: nil,
                      field: 'label',
                      label: 'label',
                      isReadOnly: false,
                      isRequired: false,
                      type: 'String',
                      widgetEdit: nil
                    }
                  ],
                  layout: [
                    { component: 'input', fieldId: 'label' },
                    { component: 'separator' }
                  ],
                  hooks: { load: false, change: ['changeHook'] }
                }
              )
            end
          end

          context 'with html block element' do
            before do
              @collection = collection_build(
                schema: {
                  actions: {
                    'Send email' => BaseAction.new(
                      scope: Types::ActionScope::SINGLE
                    )
                  }
                },
                get_form: [
                  ActionField.new(id: 'label_id', label: 'label', type: 'String'),
                  ActionLayoutElement::HtmlBlockElement.new(content: '<p>foo</p>')
                ]
              )
            end

            it 'generate schema correctly' do
              schema = described_class.build_schema(@collection, 'Send email')

              expect(schema).to eq(
                {
                  id: 'collection-0-send-email',
                  name: 'Send email',
                  submitButtonLabel: nil,
                  description: nil,
                  type: 'single',
                  baseUrl: nil,
                  endpoint: '/forest/_actions/collection/0/send-email',
                  httpMethod: 'POST',
                  redirect: nil,
                  download: false,
                  fields: [
                    {
                      defaultValue: nil,
                      description: nil,
                      field: 'label_id',
                      label: 'label',
                      isReadOnly: false,
                      isRequired: false,
                      type: 'String',
                      widgetEdit: nil
                    }
                  ],
                  layout: [
                    { component: 'input', fieldId: 'label_id' },
                    { component: 'htmlBlock', content: '<p>foo</p>' }
                  ],
                  hooks: { load: false, change: ['changeHook'] }
                }
              )
            end
          end

          context 'with row element' do
            before do
              @collection = collection_build(
                schema: {
                  actions: {
                    'Charge credit card' => BaseAction.new(
                      scope: Types::ActionScope::SINGLE
                    )
                  }
                },
                get_form: [
                  ActionLayoutElement::RowElement.new(
                    fields: [
                      ActionField.new(id: 'label_id', label: 'label', type: 'String'),
                      ActionField.new(id: 'amount_id', label: 'amount', type: 'String')
                    ]
                  )
                ]
              )
            end

            it 'generate schema correctly' do
              schema = described_class.build_schema(@collection, 'Charge credit card')

              expect(schema).to eq(
                {
                  id: 'collection-0-charge-credit-card',
                  name: 'Charge credit card',
                  submitButtonLabel: nil,
                  description: nil,
                  type: 'single',
                  baseUrl: nil,
                  endpoint: '/forest/_actions/collection/0/charge-credit-card',
                  httpMethod: 'POST',
                  redirect: nil,
                  download: false,
                  fields: [
                    {
                      field: 'label_id',
                      label: 'label',
                      type: 'String',
                      description: nil,
                      isRequired: false,
                      isReadOnly: false,
                      widgetEdit: nil,
                      defaultValue: nil
                    },
                    {
                      label: 'amount',
                      field: 'amount_id',
                      type: 'String',
                      description: nil,
                      isRequired: false,
                      isReadOnly: false,
                      widgetEdit: nil,
                      defaultValue: nil
                    }
                  ],
                  layout: [
                    {
                      component: 'row',
                      fields: [
                        { component: 'input', fieldId: 'label_id' },
                        { component: 'input', fieldId: 'amount_id' }
                      ]
                    }
                  ],
                  hooks: { load: false, change: ['changeHook'] }
                }
              )
            end
          end

          context 'with page element' do
            before do
              @collection = collection_build(
                schema: {
                  actions: {
                    'Charge credit card' => BaseAction.new(
                      scope: Types::ActionScope::SINGLE
                    )
                  }
                },
                get_form: [
                  ActionLayoutElement::PageElement.new(
                    next_button_label: 'Next',
                    previous_button_label: 'Previous',
                    elements: [
                      ActionLayoutElement::HtmlBlockElement.new(content: '<h1>Charge the credit card of the customer</h1>'),
                      ActionLayoutElement::RowElement.new(
                        fields: [
                          ActionField.new(id: 'label', label: 'label', type: 'String'),
                          ActionField.new(id: 'amount', label: 'amount', type: 'String')
                        ]
                      )
                    ]
                  )
                ]
              )
            end

            it 'generate schema correctly' do
              schema = described_class.build_schema(@collection, 'Charge credit card')

              expect(schema).to eq(
                {
                  id: 'collection-0-charge-credit-card',
                  name: 'Charge credit card',
                  submitButtonLabel: nil,
                  description: nil,
                  type: 'single',
                  baseUrl: nil,
                  endpoint: '/forest/_actions/collection/0/charge-credit-card',
                  httpMethod: 'POST',
                  redirect: nil,
                  download: false,
                  fields: [
                    {
                      field: 'label',
                      label: 'label',
                      type: 'String',
                      description: nil,
                      isRequired: false,
                      isReadOnly: false,
                      widgetEdit: nil,
                      defaultValue: nil
                    },
                    {
                      field: 'amount',
                      label: 'amount',
                      type: 'String',
                      description: nil,
                      isRequired: false,
                      isReadOnly: false,
                      widgetEdit: nil,
                      defaultValue: nil
                    }
                  ],
                  layout: [
                    {
                      component: 'page',
                      nextButtonLabel: 'Next',
                      previousButtonLabel: 'Previous',
                      elements: [
                        {
                          component: 'htmlBlock',
                          content: '<h1>Charge the credit card of the customer</h1>'
                        },
                        {
                          component: 'row',
                          fields: [
                            { component: 'input', fieldId: 'label' },
                            { component: 'input', fieldId: 'amount' }
                          ]
                        }
                      ]
                    }
                  ],
                  hooks: { load: false, change: ['changeHook'] }
                }
              )
            end
          end

          context 'with dynamic element' do
            before do
              @collection = collection_build(
                schema: {
                  actions: {
                    'Charge credit card' => BaseAction.new(
                      scope: Types::ActionScope::SINGLE,
                      form: [
                        FormLayoutElement::PageElement.new(
                          if_condition: proc { true },
                          elements: []
                        )
                      ]
                    )
                  }
                }
              )
            end

            it 'generate default loading schema' do
              schema = described_class.build_schema(@collection, 'Charge credit card')

              expect(schema).to eq(
                {
                  id: 'collection-0-charge-credit-card',
                  name: 'Charge credit card',
                  submitButtonLabel: nil,
                  description: nil,
                  type: 'single',
                  baseUrl: nil,
                  endpoint: '/forest/_actions/collection/0/charge-credit-card',
                  httpMethod: 'POST',
                  redirect: nil,
                  download: false,
                  fields: [
                    {
                      defaultValue: 'Form is loading',
                      description: '',
                      enums: nil,
                      field: 'Loading...',
                      hook: nil,
                      isReadOnly: true,
                      isRequired: false,
                      label: 'Loading...',
                      reference: nil,
                      type: 'String',
                      value: nil,
                      widgetEdit: nil
                    }
                  ],
                  hooks: { load: true, change: ['changeHook'] }
                }
              )
            end
          end

          context 'with nested dynamic element in page' do
            before do
              @collection = collection_build(
                schema: {
                  actions: {
                    'Charge credit card' => BaseAction.new(
                      scope: Types::ActionScope::SINGLE,
                      form: [
                        FormLayoutElement::PageElement.new(
                          elements: [
                            {
                              type: 'Layout',
                              component: 'HtmlBlock',
                              content: '<h1>Charge the credit card of the customer</h1>'
                            },
                            {
                              type: 'Layout',
                              component: 'Row',
                              fields: [
                                { id: 'label', label: 'label', type: 'String', if_condition: proc { true } },
                                { id: 'amount', label: 'amount', type: 'String' }
                              ]
                            }
                          ]
                        )
                      ]
                    )
                  }
                }
              )
            end

            it 'generate default loading schema' do
              schema = described_class.build_schema(@collection, 'Charge credit card')

              expect(schema).to eq(
                {
                  id: 'collection-0-charge-credit-card',
                  name: 'Charge credit card',
                  submitButtonLabel: nil,
                  description: nil,
                  type: 'single',
                  baseUrl: nil,
                  endpoint: '/forest/_actions/collection/0/charge-credit-card',
                  httpMethod: 'POST',
                  redirect: nil,
                  download: false,
                  fields: [
                    {
                      defaultValue: 'Form is loading',
                      description: '',
                      enums: nil,
                      field: 'Loading...',
                      hook: nil,
                      isReadOnly: true,
                      isRequired: false,
                      label: 'Loading...',
                      reference: nil,
                      type: 'String',
                      value: nil,
                      widgetEdit: nil
                    }
                  ],
                  hooks: { load: true, change: ['changeHook'] }
                }
              )
            end
          end

          describe 'extract_fields_and_layout' do
            before do
              @collection = collection_build(
                schema: {
                  actions: {
                    'Send email' => BaseAction.new(
                      scope: Types::ActionScope::SINGLE
                    )
                  }
                },
                get_form: [
                  ActionField.new(id: 'label_id', label: 'label', type: 'String'),
                  ActionLayoutElement::SeparatorElement.new
                ]
              )
            end

            it 'return fields and layout separately from form' do
              result = described_class.extract_fields_and_layout(@collection.get_form(nil, 'Send email'))

              expect(result).to have_key(:fields)
              expect(result).to have_key(:layout)
              expect(result[:fields]).to all(be_a(ActionField))
              expect(result[:layout]).to all(be_a(ActionLayoutElement::BaseLayoutElement))
            end
          end
        end
      end
    end
  end
end
