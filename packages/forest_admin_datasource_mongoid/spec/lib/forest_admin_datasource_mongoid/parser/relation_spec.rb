require 'spec_helper'

module ForestAdminDatasourceMongoid
  module Parser
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
    describe Validation do
      before do
        logger = instance_double(Logger, log: nil)
        allow(ForestAdminAgent::Facades::Container).to receive(:logger).and_return(logger)
      end

      let(:datasource) { ForestAdminDatasourceMongoid::Datasource.new(options: { flatten_mode: 'auto' }) }
      let(:collection) { ForestAdminDatasourceMongoid::Collection.new(datasource, model_class, [{ prefix: nil, as_fields: [], as_models: [] }]) }

      context 'when models with polymorphic relations exist' do
        let(:model_class) { User }

        it 'returns the correct mapping of polymorphic types and primary keys' do
          result = collection.get_polymorphic_types('item')

          expect(result).to eq({ 'Departure' => '_id', 'Team' => '_id' })
        end
      end

      context 'when models does not have polymorphic relation' do
        let(:model_class) { Post }

        it 'returns an empty hash' do
          result = collection.get_polymorphic_types('author')

          expect(result).to eq({})
        end
      end
    end
  end
end
