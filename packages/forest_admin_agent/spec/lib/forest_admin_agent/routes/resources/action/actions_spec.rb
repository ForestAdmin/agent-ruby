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
        let(:published_book) { @datasource.get_collection('book') }

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
                'title' => ColumnSchema.new(column_type: 'String', filter_operators: [Operators::EQUAL]),
                'holder_id' => ColumnSchema.new(column_type: 'Uuid'),
                'holder' => Relations::ManyToOneSchema.new(
                  foreign_key: 'holder_id',
                  foreign_key_target: 'id',
                  foreign_collection: 'holder'
                )
              },
              segments: ['recent']
            }
          )
          collection_holder = build_collection(
            name: 'holder',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Uuid', is_primary_key: true, filter_operators: [Operators::EQUAL]),
                'national_id' => ColumnSchema.new(column_type: 'String', filter_operators: [Operators::STARTS_WITH])
              }
            }
          )

          allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)
          datasource.add_collection(collection_book)
          datasource.add_collection(collection_holder)
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
            it 'get the signed parameters and change body' do
              unsigned_request = { foo: 'value' }
              signed_request = JWT.encode(
                unsigned_request,
                Facades::Container.cache(:env_secret),
                'HS256'
              )
              args[:params][:data][:attributes][:signed_approval_request] = signed_request
              allow(@action_collection).to receive(:execute).and_return({})
              action.handle_request(args)

              expect(permissions).to have_received(:can_smart_action?) do |args, _collection, _filter_for_caller|
                expect(args[:params][:data][:attributes][:signed_approval_request]).to eq(unsigned_request)
              end
            end
          end
        end

        context 'with a bulk action run on a select-all' do
          let(:subset_query) { {} }

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
              all_records_subset_query: subset_query
            )
            allow(published_book).to receive_messages(execute: {}, get_form: [])
          end

          context 'when the list is searched and segmented' do
            let(:subset_query) { { search: 'tolkien', segment: 'recent' } }

            it 'hands the action the search and the segment of the list, minus the excluded ids' do
              action.handle_hook_request(args)

              expect(published_book).to have_received(:get_form) do |caller, action_name, data, filter, _meta|
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
                .with(published_book, condition_tree: nil, search: 'tolkien', search_extended: false)
            end
          end

          context 'when the caller filters on a related collection' do
            let(:caller_filters) do
              JSON.generate(
                {
                  aggregator: 'And',
                  conditions: [
                    { field: 'holder:national_id', operator: 'starts_with', value: '1850' },
                    { field: 'title', operator: 'equal', value: 'Dune' }
                  ]
                }
              )
            end
            let(:subset_query) { { filters: caller_filters } }
            let(:forbidden) do
              Http::Exceptions::ForbiddenError.new(
                "You cannot filter on 'holder:national_id': you are not allowed to read the 'holder' collection."
              )
            end
            let(:reaching_holder) do
              satisfy { |tree| tree&.some_leaf { |leaf| leaf.field == 'holder:national_id' } }
            end

            def applies_guarded_tree?(tree, guarded_tree)
              guarded_tree.every_leaf { |guarded| tree.some_leaf { |leaf| leaf.equal?(guarded) } }
            end

            def guarded_tree
              tree = nil
              expect(permissions).to have_received(:assert_can_read_query_fields) do |collection, applied|
                expect(collection.equal?(published_book)).to be(true), "expected the published book, got #{collection.class}"
                expect(applied.except(:condition_tree)).to eq(search: nil, search_extended: false)
                tree = applied[:condition_tree]
              end
              tree
            end

            def counted_filter
              filter = nil
              expect(permissions).to have_received(:can_smart_action?) do |caller_args, collection, filter_for_caller, action_name:|
                expect(caller_args.dig(:params, :data, :attributes, :all_records_subset_query)).to eq(subset_query)
                expect(collection.equal?(published_book)).to be(true), "expected the published book, got #{collection.class}"
                expect(action_name).to eq('foo')
                filter = filter_for_caller
              end
              filter
            end

            def refuse_holder_filters
              allow(permissions).to receive(:assert_can_read_query_fields)
                .with(published_book, hash_including(condition_tree: reaching_holder))
                .and_raise(forbidden)
            end

            it 'checks the very condition tree the authorization then counts with' do
              action.handle_request(args)

              guarded = guarded_tree
              expect(guarded.to_h).to eq(
                aggregator: 'And',
                conditions: [
                  { field: 'holder:national_id', operator: Operators::STARTS_WITH, value: '1850' },
                  { field: 'title', operator: Operators::EQUAL, value: 'Dune' }
                ]
              )
              expect(applies_guarded_tree?(counted_filter.condition_tree, guarded)).to be true
            end

            it 'refuses before the authorization can count anything, and runs nothing' do
              refuse_holder_filters

              expect { action.handle_request(args) }
                .to raise_error(Http::Exceptions::ForbiddenError, /You cannot filter on 'holder:national_id'/)
              expect(permissions).not_to have_received(:can_smart_action?)
              expect(published_book).not_to have_received(:get_form)
              expect(published_book).not_to have_received(:execute)
            end

            it 'hands the form hooks only a filter the guard checked' do
              action.handle_hook_request(args)

              guarded = guarded_tree
              expect(guarded).to reaching_holder
              expect(published_book).to have_received(:get_form) do |caller, action_name, data, filter, meta|
                expect(caller).to be_instance_of(Components::Caller)
                expect(action_name).to eq('foo')
                expect(data).to be_nil
                expect(filter).to have_attributes(search: nil, search_extended: false, segment: nil)
                expect(applies_guarded_tree?(filter.condition_tree, guarded)).to be true
                expect(meta).to eq(
                  change_field: nil, search_field: nil, search_values: {}, includeHiddenFields: false
                )
              end
            end

            it 'refuses the form hooks before they see the filter' do
              refuse_holder_filters

              expect { action.handle_hook_request(args) }
                .to raise_error(Http::Exceptions::ForbiddenError, /You cannot filter on 'holder:national_id'/)
              expect(published_book).not_to have_received(:get_form)
            end

            context 'when the caller filters are alternatives' do
              let(:caller_filters) do
                JSON.generate(
                  {
                    aggregator: 'Or',
                    conditions: [
                      { field: 'holder:national_id', operator: 'starts_with', value: '1850' },
                      { field: 'title', operator: 'equal', value: 'Dune' }
                    ]
                  }
                )
              end

              it 'counts with the guarded branch as is' do
                action.handle_request(args)

                guarded = guarded_tree
                expect(guarded).to have_attributes(aggregator: 'Or')
                expect(counted_filter.condition_tree.conditions).to include(be(guarded))
              end
            end

            %i[filters filter].each do |param|
              context "when the filters come in params[:#{param}] outside the subset query" do
                let(:subset_query) { {} }

                before { args[:params][param] = caller_filters }

                it 'refuses them all the same' do
                  refuse_holder_filters

                  expect { action.handle_request(args) }
                    .to raise_error(Http::Exceptions::ForbiddenError, /You cannot filter on 'holder:national_id'/)
                  expect(permissions).not_to have_received(:can_smart_action?)
                  expect(published_book).not_to have_received(:execute)
                end
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
