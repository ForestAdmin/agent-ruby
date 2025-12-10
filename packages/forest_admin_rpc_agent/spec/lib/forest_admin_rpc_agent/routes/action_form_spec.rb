require 'spec_helper'
require 'json'
require 'ostruct'

module ForestAdminRpcAgent
  module Routes
    include ForestAdminDatasourceRpc
    include ForestAdminDatasourceToolkit::Components::Query
    describe ActionForm do
      include_context 'with caller'
      subject(:route) { described_class.new }

      let(:filter) { ForestAdminDatasourceToolkit::Components::Query::Filter.new }
      let(:metas) { { 'meta_field' => 'value' } }
      let(:collection_name) { 'orders' }
      let(:params) do
        {
          'collection_name' => collection_name,
          'caller' => caller.to_h,
          'filter' => {},
          'metas' => metas,
          'data' => { 'field' => 'value' },
          'action' => 'some_action'
        }
      end
      let(:args) { { params: params } }
      let(:form_response) do
        [
          ForestAdminDatasourceToolkit::Components::Actions::ActionField.new(
            id: 'amount',
            label: 'amount',
            type: 'Number',
            description: 'The amount (USD) to charge the credit card. Example: 42.50',
            is_read_only: false,
            is_required: true,
            value: nil,
            watch_changes: false,
            widget: nil
          ),
          ForestAdminDatasourceToolkit::Components::Actions::ActionField.new(
            id: 'label',
            label: 'label',
            type: 'String',
            is_read_only: false,
            is_required: false,
            value: nil,
            watch_changes: false,
            widget: nil
          ),
          ForestAdminDatasourceToolkit::Components::Actions::WidgetField::FilePickerField.new(
            id: 'product picture',
            label: 'product picture',
            type: 'File',
            is_read_only: false,
            is_required: false,
            value: nil,
            watch_changes: false,
            widget: 'FilePicker',
            extensions: ['png', 'jpg'],
            max_size_mb: 20
          )
        ]
      end
      let(:expected_response) { form_response.map(&:as_json).to_json }
      let(:response) { instance_double(Faraday::Response, success?: true, body: form_response.map(&:as_json), headers: {}) }
      let(:faraday_connection) { instance_double(Faraday::Connection) }

      before do
        collection_schema = {
          name: collection_name,
          fields: {
            id: {
              column_type: 'Number',
              filter_operators: %w[present greater_than],
              is_primary_key: true,
              is_read_only: false,
              is_sortable: true,
              default_value: nil,
              enum_values: [],
              validation: [],
              type: 'Column'
            },
            name: {
              column_type: 'String',
              filter_operators: %w[in present i_contains contains],
              is_primary_key: false,
              is_read_only: false,
              is_sortable: true,
              default_value: nil,
              enum_values: [],
              validation: [],
              type: 'Column'
            }
          },
          countable: true,
          searchable: true,
          charts: [],
          segments: [],
          actions: {}
        }
        @datasource = ForestAdminDatasourceRpc::Datasource.new(
          {},
          { collections: [collection_schema], charts: [], rpc_relations: [] }
        )
        ForestAdminRpcAgent::Agent.instance.add_datasource(@datasource)
        ForestAdminRpcAgent::Agent.instance.build

        allow(ForestAdminDatasourceToolkit::Components::Query::FilterFactory)
          .to receive(:from_plain_object)
          .and_return(filter)

        collection = @datasource.get_collection(collection_name)
        allow(collection).to receive(:get_form).and_return(form_response)

        allow(Faraday).to receive(:new).and_return(faraday_connection)
        allow(faraday_connection).to receive(:send).and_return(response)
      end

      describe '#handle_request' do
        context 'when collection_name is provided' do
          it 'executes the action on the collection and returns the form response' do
            response = route.handle_request(args)
            expect(response).to eq(form_response)
          end
        end

        context 'when collection_name is missing' do
          let(:params) { {} }

          it 'returns an empty hash' do
            response = route.handle_request(args)
            expect(response).to eq({})
          end
        end
      end

      # rubocop:disable Style/OpenStructUse
      # rubocop:disable RSpec/VerifiedDoubles
      describe '#encode_file_element' do
        context 'when element is of type "File"' do
          let(:file_element) { OpenStruct.new(type: 'File', value: double('File')) }
          let(:elements) { [file_element] }

          before do
            allow(file_element).to receive(:value).and_return('data:uri')
          end

          it 'encodes file element to data URI' do
            route.encode_file_element(elements)
            expect(file_element.value).to eq('data:uri')
          end
        end

        context 'when element is not of type "File"' do
          let(:non_file_element) { double('NonFileElement', type: 'Text') }
          let(:elements) { [non_file_element] }

          it 'does not alter the element' do
            result = route.encode_file_element(elements)
            expect(result.first).to eq(non_file_element)
          end
        end
      end
      # rubocop:enable Style/OpenStructUse
      # rubocop:enable RSpec/VerifiedDoubles
    end
  end
end
