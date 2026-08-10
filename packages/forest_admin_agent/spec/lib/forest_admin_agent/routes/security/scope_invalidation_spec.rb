require 'spec_helper'

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
                'timezone' => 'Europe/Paris'
              }
            }
          end
          let(:permissions) { class_double(ForestAdminAgent::Services::Permissions).as_stubbed_const }

          before do
            allow(permissions).to receive(:new).and_return(instance_double(ForestAdminAgent::Services::Permissions))
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

          it 'rejects the request with no Authorization header' do
            expect { scope_invalidation.handle_request(args.merge(headers: {})) }.to raise_error(
              ForestAdminAgent::Http::Exceptions::UnauthorizedError
            )
            expect(permissions).not_to have_received(:invalidate_cache)
          end

          it 'checks the ip against the whitelist when the request carries a remote ip' do
            allow(ForestAdminAgent::Facades::Whitelist).to receive(:check_ip)
            scope_invalidation.handle_request(
              args.merge(headers: args[:headers].merge('action_dispatch.remote_ip' => '10.0.0.1'))
            )
            expect(ForestAdminAgent::Facades::Whitelist).to have_received(:check_ip).with('10.0.0.1')
          end
        end
      end
    end
  end
end
