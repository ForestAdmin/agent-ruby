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

      let(:datasource) { instance_double(Datasource) }
      let(:collection) { instance_double(Collection) }
      let(:filter) { instance_double(ForestAdminDatasourceToolkit::Components::Query::Filter) }
      let(:metas) { { 'meta_field' => 'value' } }

      let(:params) do
        {
          'collection_name' => 'users',
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
      let(:expected_response) { form_response.to_json }

      before do
        allow(ForestAdminRpcAgent::Facades::Container).to receive(:datasource).and_return(datasource)
        allow(datasource).to receive(:get_collection).with('users').and_return(collection)
        allow(FilterFactory).to receive(:from_plain_object).with({}).and_return(filter)

        allow(collection).to receive(:get_form).with(instance_of(ForestAdminDatasourceToolkit::Components::Caller),
                                                     'some_action', { 'field' => 'value' }, filter, metas)
                                               .and_return(form_response)
        allow(form_response).to receive(:to_json).and_return(expected_response)
      end

      describe '#handle_request' do
        context 'when collection_name is provided' do
          it 'executes the action on the collection and returns the form response' do
            response = route.handle_request(args)
            expect(response).to eq(expected_response)
          end
        end

        context 'when collection_name is missing' do
          let(:params) { {} }

          it 'returns an empty JSON object' do
            response = route.handle_request(args)
            expect(response).to eq('{}')
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
            allow(ForestAdminAgent::Utils::Schema::ForestValueConverter)
              .to receive(:make_data_uri)
              .with(file_element.value)
              .and_return('data:uri')

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
