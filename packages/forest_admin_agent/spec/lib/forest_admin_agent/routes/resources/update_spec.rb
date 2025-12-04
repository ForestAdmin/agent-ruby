require 'spec_helper'
require 'singleton'
require 'ostruct'

module ForestAdminAgent
  module Routes
    module Resources
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminDatasourceToolkit::Schema
      describe Update do
        include_context 'with caller'
        subject(:update) { described_class.new }
        let(:args) do
          {
            headers: { 'HTTP_AUTHORIZATION' => bearer },
            params: {
              'collection_name' => 'book',
              'timezone' => 'Europe/Paris'
            }
          }
        end
        let(:permissions) { instance_double(ForestAdminAgent::Services::Permissions) }

        before do
          allow(ForestAdminAgent::Services::Permissions).to receive(:new).and_return(permissions)
          allow(permissions).to receive_messages(can?: true, get_scope: nil)
        end

        it 'adds the route forest_store' do
          update.setup_routes
          expect(update.routes.include?('forest_update')).to be true
          expect(update.routes.length).to eq 1
        end

        describe 'handle_request' do
          before do
            book_class = Struct.new(:id, :title, :published_at, :price) do
              def respond_to?(arg)
                return false if arg == :each

                super
              end
            end
            stub_const('Book', book_class)
            @datasource = Datasource.new
            collection = build_collection(
              name: 'book',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(
                    column_type: 'Number',
                    is_primary_key: true,
                    filter_operators: [Operators::IN, Operators::EQUAL]
                  ),
                  'title' => ColumnSchema.new(column_type: 'String')
                }
              }
            )

            allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)
            @datasource.add_collection(collection)
            ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(@datasource)
            ForestAdminAgent::Builder::AgentFactory.instance.build
          end

          it 'call update and return an serialized content' do
            args[:params][:data] = { attributes: { 'title' => 'Harry potter and the goblet of fire' } }
            args[:params]['id'] = '1'
            book = { 'id' => 1, 'title' => 'Harry potter and the goblet of fire' }

            allow(@datasource.get_collection('book')).to receive_messages(list: [book], update: true)
            result = update.handle_request(args)
            expect(result[:name]).to eq('book')
            expect(result[:content]).to eq(
              'data' =>
                {
                  'type' => 'book',
                  'id' => '1',
                  'attributes' => {
                    'id' => 1,
                    'title' => 'Harry potter and the goblet of fire'
                  },
                  'links' => { 'self' => '/forest/book/1' }
                }
            )
          end

          it 'call update with the expected args' do
            args[:params][:data] = { attributes: { 'title' => 'Harry potter and the goblet of fire' } }
            args[:params]['id'] = '1'
            book = { 'id' => 1, 'title' => 'Harry potter and the goblet of fire' }
            allow(@datasource.get_collection('book')).to receive_messages(list: [book], update: true)
            update.handle_request(args)

            expect(@datasource.get_collection('book')).to have_received(:update) do |caller, filter, data|
              expect(caller).to be_instance_of(Components::Caller)
              expect(data).to eq({ 'title' => 'Harry potter and the goblet of fire' })
              expect(filter.condition_tree.to_h).to eq(field: 'id', operator: Operators::EQUAL, value: 1)
            end
          end

          describe 'with polymorphic many to one relation' do
            it 'call update with polymorphic foreign key and type' do
              collection_company = build_collection(
                name: 'company',
                schema: {
                  fields: {
                    'id' => ColumnSchema.new(
                      column_type: 'Number',
                      is_primary_key: true,
                      filter_operators: [Operators::IN, Operators::EQUAL]
                    ),
                    'name' => ColumnSchema.new(column_type: 'String')
                  }
                }
              )

              collection_member = build_collection(
                name: 'member',
                schema: {
                  fields: {
                    'id' => ColumnSchema.new(
                      column_type: 'Number',
                      is_primary_key: true,
                      filter_operators: [Operators::IN, Operators::EQUAL]
                    ),
                    'memberable_id' => ColumnSchema.new(column_type: 'Number'),
                    'memberable_type' => ColumnSchema.new(column_type: 'String'),
                    'memberable' => Relations::PolymorphicManyToOneSchema.new(
                      foreign_collections: ['company'],
                      foreign_key: 'memberable_id',
                      foreign_key_type_field: 'memberable_type',
                      foreign_key_targets: { 'company' => 'id' }
                    )
                  }
                }
              )

              @datasource.add_collection(collection_company)
              @datasource.add_collection(collection_member)

              args[:params][:data] = {
                attributes: {},
                relationships: { 'memberable' => { 'data' => { 'type' => 'Company', 'id' => 5 } } }
              }
              args[:params]['collection_name'] = 'member'
              args[:params]['id'] = '1'
              member = { 'id' => 1, 'memberable_id' => 5, 'memberable_type' => 'Company' }
              allow(@datasource.get_collection('member')).to receive_messages(list: [member], update: true)

              update.handle_request(args)
              expect(@datasource.get_collection('member')).to have_received(:update) do |caller, filter, data|
                expect(caller).to be_instance_of(Components::Caller)
                expect(data).to eq({ 'memberable_id' => 5, 'memberable_type' => 'Company' })
                expect(filter.condition_tree.to_h).to eq(field: 'id', operator: Operators::EQUAL, value: 1)
              end
            end
          end
        end
      end
    end
  end
end
