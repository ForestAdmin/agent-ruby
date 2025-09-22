require 'spec_helper'
require 'rails'
require 'action_dispatch'

module ForestAdminRpcAgent
  module Routes
    describe BaseRoute do
      subject(:route) { described_class.new('/test', 'get', 'test_route') }

      describe '#initialize' do
        it 'sets the correct attributes' do
          expect(route.instance_variable_get(:@url)).to eq('/test')
          expect(route.instance_variable_get(:@method)).to eq('get')
          expect(route.instance_variable_get(:@name)).to eq('test_route')
        end
      end

      describe '#registered' do
        # TODO: WHEN SINATRA ROUTES ARE CORRECTLY IMPLEMENTED
        # context 'when the app is a Sinatra::Base' do
        #   let(:sinatra_app) { Class.new(Sinatra::Base) }
        # end

        context 'when the app is an ActionDispatch::Routing::Mapper' do
          let(:rails_app) { Class.new(Rails::Application) }
          let(:rails_router) { ActionDispatch::Routing::Mapper.new(rails_app.routes) }

          before do
            allow(route).to receive(:register_rails)
          end

          it 'calls register_rails' do
            route.registered(rails_router)
            expect(route).to have_received(:register_rails).with(rails_router)
          end
        end

        context 'when the app is neither Sinatra nor Rails' do
          let(:unknown_app) { Object.new }

          it 'raises NotImplementedError' do
            expect { route.registered(unknown_app) }
              .to raise_error(NotImplementedError)
          end
        end
      end

      describe '#register_rails' do
        let(:rails_router) { instance_double(ActionDispatch::Routing::Mapper) }
        let(:middleware) { instance_double(ForestAdminRpcAgent::Middleware::Authentication) }
        let(:request) do
          instance_double(ActionDispatch::Request, query_parameters: {}, request_parameters: {}, env: {})
        end

        before do
          allow(ActionDispatch::Request).to receive(:new).and_return(request)
          allow(ForestAdminRpcAgent::Middleware::Authentication)
            .to receive(:new)
            .and_return(middleware)

          allow(middleware).to receive(:call).and_return([200, {}, ['OK']])
          allow(rails_router).to receive(:match)
        end

        it 'registers the route in Rails' do
          route.send(:register_rails, rails_router)

          expect(rails_router).to have_received(:match).with(
            '/test',
            defaults: { format: 'json' },
            to: kind_of(Proc),
            via: 'get',
            as: 'test_route',
            route_alias: 'test_route'
          )
        end
      end
    end
  end
end
