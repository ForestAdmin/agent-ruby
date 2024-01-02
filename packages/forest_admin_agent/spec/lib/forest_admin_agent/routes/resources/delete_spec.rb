require 'spec_helper'
require 'singleton'
require 'ostruct'
require 'shared/caller'

module ForestAdminAgent
  module Routes
    module Resources
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminDatasourceToolkit::Schema
      describe Delete do
        include_context 'with caller'
        subject(:delete) { described_class.new }
        let(:args) do
          {
            headers: { 'HTTP_AUTHORIZATION' => bearer },
            params: params
          }
        end
        let(:permissions) { instance_double(ForestAdminAgent::Services::Permissions) }

        before do
          allow(ForestAdminAgent::Services::Permissions).to receive(:new).and_return(permissions)
          allow(permissions).to receive_messages(can?: true, get_scope: nil)
        end

        it 'adds the route forest_store' do
          delete.setup_routes
          expect(delete.routes.include?('forest_delete')).to be true
          expect(delete.routes.include?('forest_delete_bulk')).to be true
          expect(delete.routes.length).to eq 2
        end

        describe 'handle requests' do
          before do
            user_class = Struct.new(:id, :first_name, :last_name) do
              def respond_to?(arg)
                return false if arg == :each

                super(arg)
              end
            end
            stub_const('User', user_class)

            datasource = Datasource.new

            collection = instance_double(
              Collection,
              name: 'user',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(
                    column_type: 'Number',
                    is_primary_key: true,
                    filter_operators: [Operators::IN, Operators::EQUAL]
                  ),
                  'first_name' => ColumnSchema.new(column_type: 'String'),
                  'last_name' => ColumnSchema.new(column_type: 'String')
                }
              },
              delete: true
            )

            allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)
            datasource.add_collection(collection)
            ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(datasource)
            ForestAdminAgent::Builder::AgentFactory.instance.build

            @datasource = ForestAdminAgent::Facades::Container.datasource
            allow(@datasource.get_collection('user')).to receive(:delete)
          end

          context 'with simple request' do
            let(:params) do
              {
                'collection_name' => 'user',
                'timezone' => 'Europe/Paris',
                'id' => 1
              }
            end

            it 'returns an empty content and a 204 status' do
              result = delete.handle_request(args)

              expect(result[:content]).to be_nil
              expect(result[:status]).to eq 204
            end

            it 'call delete function with expected args' do
              delete.handle_request(args)

              expect(@datasource.get_collection('user')).to have_received(:delete) do |caller, filter|
                expect(caller).to be_instance_of(Components::Caller)
                expect(filter.condition_tree.to_h).to eq(field: 'id', operator: Operators::EQUAL, value: 1)
              end
            end
          end

          context 'with bulk request' do
            let(:params) do
              {
                'collection_name' => 'user',
                'timezone' => 'Europe/Paris',
                'data' => {
                  'attributes' => {
                    'ids' => %w[1 2 3],
                    'collection_name' => 'Car',
                    'parent_collection_name' => nil,
                    'parent_collection_id' => nil,
                    'parent_association_name' => nil,
                    'all_records' => false,
                    'all_records_subset_query' => {
                      'fields[Car]' => 'id,model,brand',
                      'page[number]' => 1,
                      'page[size]' => 15
                    },
                    'all_records_ids_excluded' => [],
                    'smart_action_id' => nil
                  },
                  'type' => 'action-requests'
                }
              }
            end

            it 'returns an empty content and a 204 status' do
              result = delete.handle_request_bulk(args)

              expect(result[:content]).to be_nil
              expect(result[:status]).to eq 204
            end

            it 'call delete function with filters for only ids selected' do
              delete.handle_request_bulk(args)

              expect(@datasource.get_collection('user')).to have_received(:delete) do |caller, filter|
                expect(caller).to be_instance_of(Components::Caller)
                expect(filter.condition_tree.to_h).to eq(field: 'id', operator: Operators::IN, value: [1, 2, 3])
              end
            end

            it 'call delete function with filters for only ids no selected' do
              args[:params]['data']['attributes']['all_records'] = true
              args[:params]['data']['attributes']['all_records_ids_excluded'] = %w[1 2 3]
              delete.handle_request_bulk(args)

              expect(@datasource.get_collection('user')).to have_received(:delete) do |caller, filter|
                expect(caller).to be_instance_of(Components::Caller)
                expect(filter.condition_tree.to_h).to eq(field: 'id', operator: Operators::NOT_IN, value: [1, 2, 3])
              end
            end
          end
        end
      end
    end
  end
end
