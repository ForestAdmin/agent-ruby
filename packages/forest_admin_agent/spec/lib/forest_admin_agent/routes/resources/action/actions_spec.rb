require 'spec_helper'
require 'singleton'
require 'ostruct'

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
          collection_book = build_collection(
            name: 'book',
            schema: {
              fields: {
                'id' => ColumnSchema.new(
                  column_type: 'Uuid',
                  is_primary_key: true,
                  filter_operators: [Operators::EQUAL, Operators::IN, Operators::NOT_EQUAL]
                ),
                'title' => ColumnSchema.new(column_type: 'String')
              },
              segments: ['recent']
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
            assert_can_read_query_fields: nil,
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

          it 'checks the action the route serves, from a record selection built once' do
            allow(@action_collection).to receive(:execute).and_return({})
            allow(ForestAdminAgent::Utils::QueryStringParser).to receive(:parse_condition_tree).and_call_original

            action.handle_request(args)

            expect(permissions).to(have_received(:can_smart_action?) { |*, action_name:| expect(action_name).to eq('foo') })
            expect(ForestAdminAgent::Utils::QueryStringParser).to have_received(:parse_condition_tree).once
          end

          describe 'when the collection of the URL does not serve this action' do
            let(:published_book) { @datasource.get_collection('book') }

            def declare_actions(actions)
              allow(published_book).to receive(:schema).and_wrap_original do |original|
                original.call.merge(actions: actions)
              end
            end

            it 'refuses a collection without the action' do
              declare_actions({})

              expect { action.handle_request(args) }.to raise_error(
                Http::Exceptions::BadRequestError, 'The collection book does not have this smart action'
              )
              expect(permissions).not_to have_received(:can_smart_action?)
            end

            it 'refuses a collection serving the action under another index' do
              declare_actions({ 'bar' => published_book.schema[:actions]['foo'], 'foo' => published_book.schema[:actions]['foo'] })

              expect { action.handle_request(args) }.to raise_error(Http::Exceptions::BadRequestError)
            end

            it 'refuses the form hooks too' do
              declare_actions({})

              expect { action.handle_hook_request(args) }.to raise_error(Http::Exceptions::BadRequestError)
            end
          end

          context 'when the request contains requester_id' do
            it 'reject with UnprocessableError (prevent forged request)' do
              args[:params][:data][:attributes][:requester_id] = 'requester_id'
              allow(@action_collection).to receive(:execute)

              expect { action.handle_request(args) }.to raise_error(Http::Exceptions::UnprocessableError)
            end
          end

          context 'when the request is an approval' do
            it 'hands the checker the decoded request and uses the signed payload' do
              unsigned_request = {
                data: {
                  attributes: {
                    requester_id: 20,
                    ids: ['123e4567-e89b-12d3-a456-426614174999'],
                    collection_name: 'book',
                    values: {}
                  }
                }
              }
              signed_request = JWT.encode(
                unsigned_request,
                Facades::Container.cache(:env_secret),
                'HS256'
              )
              args[:params][:data][:attributes][:signed_approval_request] = signed_request
              args[:params][:data][:attributes][:values] = { 'firstname' => 'John' }
              allow(@action_collection).to receive(:execute).and_return({})
              action.handle_request(args)

              expect(permissions).to have_received(:can_smart_action?) do |args, _collection, _filter_for_caller|
                expect(args[:params][:data][:attributes][:signed_approval_request][:data][:attributes][:requester_id]).to eq(20)
                expect(args[:params][:data][:attributes][:ids]).to eq(['123e4567-e89b-12d3-a456-426614174999'])
              end
              expect(@action_collection).to have_received(:execute) do |_caller, _action, data, _filter|
                expect(data).to eq({})
              end
            end
          end
        end

        context 'when the request carries a signed approval request' do
          let(:book_id) { '123e4567-e89b-12d3-a456-426614174000' }
          let(:signed_id) { '123e4567-e89b-12d3-a456-426614174999' }
          let(:other_id) { '123e4567-e89b-12d3-a456-426614174888' }

          def approval_token(attributes = {}, requester_id: 20, exp: Time.now.to_i + 600)
            JWT.encode(
              {
                data: {
                  type: 'custom-action-requests',
                  id: 42,
                  attributes: {
                    requester_id: requester_id,
                    ids: [signed_id],
                    collection_name: 'book',
                    smart_action_id: 'smartActionId',
                    values: {},
                    parent_collection_name: nil,
                    parent_collection_id: nil,
                    parent_association_name: nil,
                    all_records: false,
                    all_records_subset_query: nil
                  }.merge(attributes)
                },
                approver: 1,
                iat: Time.now.to_i,
                exp: exp
              },
              Facades::Container.cache(:env_secret),
              'HS256'
            )
          end

          def approval_request(token, body_attributes = {})
            args[:params][:data][:attributes][:signed_approval_request] = token
            args[:params][:data][:attributes].merge!(body_attributes)
            args
          end

          before do
            @action_collection.add_action(
              'foo',
              ForestAdminDatasourceCustomizer::Decorators::Action::BaseAction.new(
                scope: ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope::BULK,
                form: [
                  { type: ForestAdminDatasourceCustomizer::Decorators::Action::Types::FieldType::NUMBER,
                    label: 'amount' },
                  { type: ForestAdminDatasourceCustomizer::Decorators::Action::Types::FieldType::COLLECTION,
                    label: 'customer', collection_name: 'book' }
                ]
              ) { |_context, result_builder| result_builder.success }
            )
            allow(@action_collection).to receive(:execute).and_return({})
          end

          it 'runs the action on the signed ids and hands the checker the signed requester' do
            action.handle_request(approval_request(approval_token, ids: [other_id]))

            expect(@action_collection).to have_received(:execute) do |_caller, _name, _data, filter|
              expect(filter.condition_tree.to_h).to eq({ field: 'id', operator: Operators::EQUAL, value: signed_id })
            end
            expect(permissions).to have_received(:can_smart_action?) do |a, _collection, _filter|
              expect(a.dig(:params, :data, :attributes, :signed_approval_request, :data, :attributes, :requester_id)).to eq(20)
            end
          end

          it 'runs the action with the signed values' do
            action.handle_request(approval_request(approval_token({ 'values' => { 'amount' => 10 } }), values: { 'amount' => 999_999 }))

            expect(@action_collection).to have_received(:execute) do |_caller, _name, data, _filter|
              expect(data).to eq('amount' => 10)
            end
          end

          it 'parses the signed values like the frontend ones: a collection field is unpacked, not passed through' do
            action.handle_request(approval_request(approval_token({ 'values' => { 'customer' => book_id } })))

            expect(@action_collection).to have_received(:execute) do |_caller, _name, data, _filter|
              expect(data).to eq('customer' => [book_id])
            end
          end

          it 'refuses a token signed for another collection before any permission check' do
            expect do
              action.handle_request(approval_request(approval_token({ 'collection_name' => 'other_collection' })))
            end.to raise_error(ForestAdminAgent::Http::Exceptions::ForbiddenError)

            expect(permissions).not_to have_received(:can_smart_action?)
            expect(@action_collection).not_to have_received(:execute)
          end

          it 'refuses a token that does not say which collection it was signed for' do
            expect do
              action.handle_request(approval_request(approval_token({ 'collection_name' => nil })))
            end.to raise_error(ForestAdminAgent::Http::Exceptions::ForbiddenError)

            expect(@action_collection).not_to have_received(:execute)
          end

          it 'refuses a token whose data does not carry server-shaped attributes' do
            [JWT.encode({ data: { type: 'custom-action-requests' } }, Facades::Container.cache(:env_secret), 'HS256'),
             JWT.encode({ data: [] }, Facades::Container.cache(:env_secret), 'HS256')].each do |token|
              expect { action.handle_request(approval_request(token)) }
                .to raise_error(ForestAdminAgent::Http::Exceptions::ForbiddenError)
            end

            expect(@action_collection).not_to have_received(:execute)
          end

          it 'refuses a token that selects all records instead of naming them' do
            token = approval_token({ 'all_records' => true, 'all_records_subset_query' => { 'search' => 'needle' } })

            expect { action.handle_request(approval_request(token)) }
              .to raise_error(ForestAdminAgent::Http::Exceptions::ForbiddenError)

            expect(permissions).not_to have_received(:can_smart_action?)
            expect(@action_collection).not_to have_received(:execute)
          end

          it 'refuses an expired token with a 403-class error, not a 500' do
            expect do
              action.handle_request(approval_request(approval_token(exp: Time.now.to_i - 10)))
            end.to raise_error(ForestAdminAgent::Http::Exceptions::ForbiddenError)

            expect(@action_collection).not_to have_received(:execute)
          end

          it 'refuses a token signed with another secret, or not a token at all' do
            other_secret_token = JWT.encode({ data: { attributes: { ids: [signed_id], collection_name: 'book' } } }, 'not-the-env-secret', 'HS256')

            [other_secret_token, 'abc', true, 123, [], {}, false].each do |token|
              expect { action.handle_request(approval_request(token)) }
                .to raise_error(ForestAdminAgent::Http::Exceptions::ForbiddenError)
            end

            expect(@action_collection).not_to have_received(:execute)
          end

          it 'applies the outer query filters within the signed selection' do
            args[:params][:filters] = { field: 'id', operator: Operators::EQUAL, value: book_id }

            action.handle_request(approval_request(approval_token({ 'ids' => [book_id, signed_id] }), ids: [book_id]))

            expect(@action_collection).to have_received(:execute) do |_caller, _name, _data, filter|
              expect(filter.condition_tree.to_h).to eq(
                {
                  aggregator: 'And',
                  conditions: [
                    { field: 'id', operator: Operators::EQUAL, value: book_id },
                    { field: 'id', operator: Operators::IN, value: [book_id, signed_id] }
                  ]
                }
              )
            end
          end
        end

        context 'with a bulk action run on a searched, segmented select-all' do
          before do
            @action_collection.add_action(
              'foo',
              ForestAdminDatasourceCustomizer::Decorators::Action::BaseAction.new(
                scope: ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope::BULK
              ) do |_context, result_builder|
                result_builder.success
              end
            )
            args[:params][:data][:attributes].merge!(
              ids: [],
              all_records: true,
              all_records_ids_excluded: ['123e4567-e89b-12d3-a456-426614174000'],
              all_records_subset_query: { search: 'tolkien', segment: 'recent' }
            )
            allow(@action_collection).to receive(:get_form).and_return([])
          end

          it 'hands the action the search and the segment of the list, minus the excluded ids' do
            action.handle_hook_request(args)

            expect(@action_collection).to have_received(:get_form) do |caller, action_name, data, filter, _meta|
              expect(caller).to be_instance_of(Components::Caller)
              expect(action_name).to eq('foo')
              expect(data).to be_nil
              expect(filter).to have_attributes(
                search: 'tolkien', search_extended: false, segment: 'recent', sort: nil, page: nil
              )
              expect(filter.condition_tree.to_h).to eq(
                { field: 'id', operator: Operators::NOT_EQUAL, value: '123e4567-e89b-12d3-a456-426614174000' }
              )
            end
          end

          it 'checks the caller can read the fields the search reaches' do
            action.handle_hook_request(args)

            expect(permissions).to have_received(:assert_can_read_query_fields)
              .with(@datasource.get_collection('book'), condition_tree: nil, search: 'tolkien', search_extended: false)
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
              allow(@action_collection).to receive(:execute).and_return({})
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

            it 'uses datasource to build field schema' do
              field = { type: ForestAdminDatasourceCustomizer::Decorators::Action::Types::FieldType::STRING, label: 'firstname' }
              allow(@action_collection).to receive(:get_form).and_return([field])
              allow(ForestAdminAgent::Utils::Schema::GeneratorAction).to receive_messages(build_field_schema: {}, extract_fields_and_layout: { fields: [field], layout: [] })

              action.handle_hook_request(args)

              expect(ForestAdminAgent::Utils::Schema::GeneratorAction).to have_received(:build_field_schema)
                .with(@datasource, field)
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
              allow(@action_collection).to receive(:execute).and_return({})
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
              allow(@action_collection).to receive(:execute).and_return({})
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
