require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Plugins
    describe AddExternalRelation do
      let(:plugin) { described_class.new }

      let(:collection) do
        instance_double(ForestAdminDatasourceToolkit::Collection)
      end

      let(:collection_customizer) do
        instance_double(
          ForestAdminDatasourceCustomizer::CollectionCustomizer,
          collection: collection,
          add_field: nil
        )
      end

      let(:primary_keys) { ['id'] }

      before do
        allow(ForestAdminDatasourceToolkit::Utils::Schema).to receive(:primary_keys)
          .with(collection).and_return(primary_keys)
      end

      it 'adds a computed field to the collection' do
        list_records_proc = proc { |record, context| "#{record}-#{context}" }

        plugin.run(
          nil,
          collection_customizer,
          {
            name: 'external_users',
            schema: 'String',
            listRecords: list_records_proc
          }
        )

        expect(collection_customizer).to have_received(:add_field) do |name, definition|
          expect(name).to eq('external_users')
          expect(definition.column_type).to eq(['String'])
          expect(definition.dependencies).to eq(primary_keys)
          expect(definition.get_values(['test'], 'foo')).to eq(['test-foo'])
        end
      end

      it 'raises an error when options are missing required keys' do
        expect do
          plugin.run(nil, collection_customizer, { name: 'missing_schema' })
        end.to raise_error(ForestAdminAgent::Http::Exceptions::BadRequestError, 'The options parameter must contains the following keys: `name, schema, listRecords`')
      end
    end
  end
end
