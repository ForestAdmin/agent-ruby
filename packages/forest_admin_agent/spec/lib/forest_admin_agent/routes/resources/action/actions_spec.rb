require 'spec_helper'
require 'singleton'
require 'ostruct'
require 'shared/caller'
require 'json'

module ForestAdminAgent
  module Routes
    module Action
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Schema
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes

      describe Actions do
        include_context 'with caller'
        let(:args) do
          {
            headers: { 'HTTP_AUTHORIZATION' => bearer },
            params: {
              'collection_name' => 'book',
              'timezone' => 'Europe/Paris',
              data: {
                attributes: {
                  ids: ['123e4567-e89b-12d3-a456-426614174000'],
                  all_records: false,
                  all_records_ids_excluded: [],
                  values: {}
                }
              }
            }
          }
        end
        let(:permissions) { instance_double(ForestAdminAgent::Services::Permissions) }

        before do
          datasource = Datasource.new
          collection_book = collection_build(
            name: 'book',
            schema: {
              fields: {
                'id' => ColumnSchema.new(
                  column_type: 'Uuid',
                  is_primary_key: true,
                  filter_operators: [Operators::EQUAL, Operators::IN]
                )
              }
            }
          )

          allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)
          datasource.add_collection(collection_book)
          @agent = ForestAdminAgent::Builder::AgentFactory.instance
          @agent.add_datasource(datasource)
          @agent.build

          @datasource = ForestAdminAgent::Facades::Container.datasource
          @action_collection = @agent.customizer.stack.action.get_collection('book')

          allow(ForestAdminAgent::Services::Permissions).to receive(:new).and_return(permissions)
          allow(permissions).to receive_messages(
            can_smart_action?: true,
            get_scope: nil,
            get_user_data: {
              id: 1,
              firstName: 'John',
              lastName: 'Doe',
              fullName: 'John Doe',
              email: 'johndoe@forestadmin.com',
              tags: { 'foo' => 'bar' },
              roleId: 1,
              permissionLevel: 'admin'
            },
            get_team: { id: 100, name: 'Operations' }
          )
        end

        subject(:action) { described_class.new(@action_collection, 'foo') }

        it 'adds the routes for "foo" action' do
          action.setup_routes

          expect(action.routes.keys).to eq(
            %w[forest_action_book__foo forest_action_book__foo_load forest_action_book__foo_change forest_action_book__foo_search]
          )
        end

        describe 'checking user authorization' do
          before do
            @action_collection.add_action(
              'foo',
              ForestAdminDatasourceCustomizer::Decorators::Action::BaseAction.new(
                scope: ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope::GLOBAL,
                form: [
                  { type: ForestAdminDatasourceCustomizer::Decorators::Action::Types::FieldType::STRING, label: 'firstname' }
                ]
              ) do |_context, result_builder|
                result_builder.success
              end
            )
          end

          context 'when the request contains requester_id' do
            it 'reject with UnprocessableError (prevent forged request)' do
              args[:params][:data][:attributes][:requester_id] = 'requester_id'
              allow(@action_collection).to receive(:execute)

              expect { action.handle_request(args) }.to raise_error(Http::Exceptions::UnprocessableError)
            end
          end

          context 'when the request is an approval' do
            it 'get the signed parameters and change body' do
              unsigned_request = { foo: 'value' }
              signed_request = JWT.encode(
                unsigned_request,
                Facades::Container.cache(:env_secret),
                'HS256'
              )
              args[:params][:data][:attributes][:signed_approval_request] = signed_request
              allow(@action_collection).to receive(:execute)
              action.handle_request(args)

              expect(permissions).to have_received(:can_smart_action?) do |args, _collection, _filter_for_caller|
                expect(args[:params][:data][:attributes][:signed_approval_request]).to eq(unsigned_request)
              end
            end
          end
        end

        context 'with a single action used from list-view, detail-view & summary' do
          before do
            @action_collection.add_action(
              'foo',
              ForestAdminDatasourceCustomizer::Decorators::Action::BaseAction.new(
                scope: ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope::SINGLE,
                form: [
                  { type: ForestAdminDatasourceCustomizer::Decorators::Action::Types::FieldType::STRING, label: 'firstname' }
                ]
              ) do |_context, result_builder|
                result_builder.success
              end
            )
          end

          describe 'handle_request' do
            it 'delegate to collection with good params' do
              args[:params][:data][:attributes][:values] = { 'firstname' => 'John' }
              allow(@action_collection).to receive(:execute)
              action.handle_request(args)
              expect(@action_collection).to have_received(:execute) do |caller, action, data, filter|
                expect(caller).to be_instance_of(Components::Caller)
                expect(action).to eq('foo')
                expect(data).to eq({ 'firstname' => 'John' })
                expect(filter.condition_tree.to_h).to eq(
                  { field: 'id', operator: Operators::EQUAL, value: '123e4567-e89b-12d3-a456-426614174000' }
                )
              end
            end
          end

          describe 'handle_hook' do
            it 'generate a clean form if called without params' do
              allow(@action_collection).to receive(:get_form).and_return([])
              action.handle_hook_request(args)
              expect(@action_collection).to have_received(:get_form) do |caller, action, data, filter, meta|
                expect(caller).to be_instance_of(Components::Caller)
                expect(action).to eq('foo')
                expect(data).to be_nil
                expect(filter.condition_tree.to_h).to eq(
                  { field: 'id', operator: Operators::EQUAL, value: '123e4567-e89b-12d3-a456-426614174000' }
                )
                expect(meta).to eq(
                  {
                    change_field: nil,
                    search_field: nil,
                    search_values: {},
                    includeHiddenFields: false
                  }
                )
              end
            end
          end
        end

        context 'with a bulk action used from list-view, detail-view & summary' do
          before do
            @action_collection.add_action(
              'foo',
              ForestAdminDatasourceCustomizer::Decorators::Action::BaseAction.new(
                scope: ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope::BULK,
                form: [
                  { type: ForestAdminDatasourceCustomizer::Decorators::Action::Types::FieldType::STRING, label: 'firstname' }
                ]
              ) do |_context, result_builder|
                result_builder.success
              end
            )
          end

          describe 'handle_request' do
            it 'delegate to collection with good params' do
              args[:params][:data][:attributes][:values] = { 'firstname' => 'John' }
              args[:params][:data][:attributes][:ids] = %w[123e4567-e89b-12d3-a456-426614174000 123e4567-e89b-12d3-a456-426614174001]
              allow(@action_collection).to receive(:execute)
              action.handle_request(args)
              expect(@action_collection).to have_received(:execute) do |caller, action, data, filter|
                expect(caller).to be_instance_of(Components::Caller)
                expect(action).to eq('foo')
                expect(data).to eq({ 'firstname' => 'John' })
                expect(filter.condition_tree.to_h).to eq(
                  { field: 'id', operator: Operators::IN, value: %w[123e4567-e89b-12d3-a456-426614174000 123e4567-e89b-12d3-a456-426614174001] }
                )
              end
            end
          end
        end

        context 'with a global action used from list-view, detail-view & summary' do
          before do
            @action_collection.add_action(
              'foo',
              ForestAdminDatasourceCustomizer::Decorators::Action::BaseAction.new(
                scope: ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope::GLOBAL,
                form: [
                  { type: ForestAdminDatasourceCustomizer::Decorators::Action::Types::FieldType::STRING, label: 'firstname' }
                ]
              ) do |_context, result_builder|
                result_builder.success
              end
            )
          end

          describe 'handle_request' do
            it 'ignore record selection' do
              args[:params][:data][:attributes][:all_records] = true
              allow(@action_collection).to receive(:execute)
              action.handle_request(args)

              expect(@action_collection).to have_received(:execute) do |caller, action, data, filter|
                expect(caller).to be_instance_of(Components::Caller)
                expect(action).to eq('foo')
                expect(data).to eq({})
                expect(filter.condition_tree).to be_nil
              end
            end
          end
        end
      end
    end
  end
end
