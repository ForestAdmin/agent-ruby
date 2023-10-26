require 'spec_helper'
require 'singleton'
require 'ostruct'
require 'shared/caller'

module ForestAdminAgent
  module Routes
    module Resources
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Schema
      describe Delete do
        include_context 'with caller'
        subject(:delete) { described_class.new }
        let(:args) do
          {
            headers: { 'HTTP_AUTHORIZATION' => bearer },
            params: {
              'collection_name' => 'book',
              'timezone' => 'Europe/Paris'
            }
          }
        end

        it 'adds the route forest_store' do
          delete.setup_routes
          expect(delete.routes.include?('forest_delete')).to be true
          expect(delete.routes.include?('forest_delete_bulk')).to be true
          expect(delete.routes.length).to eq 2
        end
      end
    end
  end
end
