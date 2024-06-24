require 'spec_helper'

module ForestAdminAgent
  module Utils
    module Schema
      include ForestAdminDatasourceToolkit::Components::Actions
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
                type: 'single',
                baseUrl: nil,
                endpoint: '/forest/_actions/collection/0/send-email',
                httpMethod: 'POST',
                redirect: nil,
                download: false,
                fields: [{ description: 'email', isRequired: true, isReadOnly: false, field: 'label', widgetEdit: nil, type: 'String', default_value: '' }],
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
                      is_generate_file: false
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
                      is_generate_file: false
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
                      is_generate_file: false
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
      end
    end
  end
end
