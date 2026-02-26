require 'spec_helper'

module ForestAdminDatasourceCustomizer
  describe CompositeDatasource do
    subject(:composite) { described_class.new }

    let(:datasource) do
      double(
        'Datasource',
        collections: {},
        schema: { charts: [] },
        live_query_connections: { 'main' => 'conn_main' }
      )
    end

    describe '#execute_native_query' do
      before { composite.add_data_source(datasource) }

      context 'when the connection exists' do
        it 'delegates to the right datasource' do
          allow(datasource).to receive(:execute_native_query).and_return([{ 'id' => 1 }])

          result = composite.execute_native_query('main', 'SELECT 1')

          expect(datasource).to have_received(:execute_native_query).with('main', 'SELECT 1', {})
          expect(result).to eq([{ 'id' => 1 }])
        end
      end

      context 'when the connection does not exist' do
        it 'raises an error with the correct connection name' do
          expect do
            composite.execute_native_query('unknown', 'SELECT 1')
          end.to raise_error(
            ForestAdminDatasourceToolkit::Exceptions::ForestException,
            /Native query connection 'unknown' is unknown\./
          )
        end
      end
    end
  end
end
