require 'spec_helper'
require 'shared/caller'

module ForestAdminAgent
  module Routes
    module Security
      describe ScopeInvalidation do
        include_context 'with caller'
        subject(:scope_invalidation) { described_class.new }

        context 'when setup the routes' do
          it 'adds the route forest_scope_invalidation' do
            scope_invalidation.setup_routes
            expect(scope_invalidation.routes.include?('forest_scope_invalidation')).to be true
            expect(scope_invalidation.routes.length).to eq 1
          end
        end

        context 'when handle the scope invalidation' do
          let(:args) do
            {
              headers: { 'HTTP_AUTHORIZATION' => bearer },
              params: {
                'collection_name' => 'user',
                'timezone' => 'Europe/Paris'
              }
            }
          end
          let(:permissions) { class_double(ForestAdminAgent::Services::Permissions).as_stubbed_const }

          before do
            allow(permissions).to receive(:invalidate_cache).with(any_args).and_return(nil)
          end

          it 'return 204 response' do
            result = scope_invalidation.handle_request(args)
            expect(result[:content]).to be_nil
            expect(result[:status]).to eq 204
          end

          it 'call the invalidate_cache method' do
            scope_invalidation.handle_request(args)

            expect(permissions).to have_received(:invalidate_cache).with('forest.rendering')
          end
        end
      end
    end
  end
end
