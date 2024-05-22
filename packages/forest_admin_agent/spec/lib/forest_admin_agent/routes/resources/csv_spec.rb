require 'spec_helper'
require 'singleton'
require 'ostruct'
require 'shared/caller'
require 'json'

module ForestAdminAgent
  module Routes
    module Resources
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminDatasourceToolkit::Schema
      describe Csv do
        include_context 'with caller'
        subject(:csv) { described_class.new }
        let(:args) do
          {
            headers: { 'HTTP_AUTHORIZATION' => bearer },
            params: {
              'collection_name' => 'user',
              'timezone' => 'Europe/Paris'
            }
          }
        end
        let(:permissions) { instance_double(ForestAdminAgent::Services::Permissions) }
        let(:csv_generator) { class_double(ForestAdminAgent::Utils::CsvGenerator).as_stubbed_const }

        before do
          user_class = Struct.new(:id, :first_name, :last_name)
          stub_const('User', user_class)

          datasource = Datasource.new
          collection = collection_build(
            name: 'user',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'first_name' => ColumnSchema.new(column_type: 'String'),
                'last_name' => ColumnSchema.new(column_type: 'String')
              }
            },
            list: [User.new(1, 'foo', 'foo')]
          )

          allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)
          datasource.add_collection(collection)
          ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(datasource)
          ForestAdminAgent::Builder::AgentFactory.instance.build
          @datasource = ForestAdminAgent::Facades::Container.datasource
          allow(@datasource.get_collection('user')).to receive(:list).and_return([User.new(1, 'foo', 'foo')])

          allow(ForestAdminAgent::Services::Permissions).to receive(:new).and_return(permissions)
          allow(permissions).to receive_messages(can?: true, get_scope: nil)
        end

        it 'adds the route forest_list_csv' do
          csv.setup_routes
          expect(csv.routes.include?('forest_list_csv')).to be true
          expect(csv.routes.length).to eq 1
        end

        context 'when call csv' do
          it 'returns an export csv' do
            allow(csv_generator).to receive(:generate).with([User.new(1, 'foo', 'foo')], %w[id first_name last_name]).and_return("id,first_name,last_name\n1,foo,foo\n")
            result = csv.handle_request(args)

            expect(@datasource.get_collection('user')).to have_received(:list) do |caller, filter, projection|
              expect(caller).to be_instance_of(Components::Caller)
              expect(filter).to be_instance_of(Components::Query::Filter)
              expect(projection).to eq(%w[id first_name last_name])
            end

            expect(csv_generator).to have_received(:generate) do |records, projection|
              expect(records).to eq([User.new(1, 'foo', 'foo')])
              expect(projection).to eq(%w[id first_name last_name])
            end
            expect(result[:filename]).to eq('user.csv')
            expect(result[:content][:export]).to eq("id,first_name,last_name\n1,foo,foo\n")
          end

          it 'with a filename should return an export csv with the filename provided' do
            args[:params][:filename] = 'filename'
            result = csv.handle_request(args)

            expect(result[:filename]).to eq('filename.csv')
            expect(result[:content][:export]).to eq("id,first_name,last_name\n1,foo,foo\n")
          end
        end
      end
    end
  end
end
