require 'spec_helper'
require 'rails'
require 'action_dispatch'

module ForestAdminRpcAgent
  module Routes
    # Test route class that implements handle_request
    class TestRoute < BaseRoute
      def handle_request(_params)
        { test: 'data' }
      end
    end

    # Test health route class that implements handle_request
    class TestHealthRoute < BaseRoute
      def handle_request(_params)
        { error: nil, message: 'Agent is running' }
      end
    end

    # Test route that raises a NotFoundError
    class TestNotFoundRoute < BaseRoute
      def handle_request(_params)
        raise ForestAdminAgent::Http::Exceptions::NotFoundError, 'Resource not found'
      end
    end

    describe BaseRoute do
      subject(:route) { TestRoute.new('/test', 'get', 'test_route') }

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

        context 'when the route is a health check (root path)' do
          subject(:health_route) { TestHealthRoute.new('/', 'get', 'health') }

          it 'registers the route with / path' do
            health_route.send(:register_rails, rails_router)

            expect(rails_router).to have_received(:match).with(
              '/',
              defaults: { format: 'json' },
              to: kind_of(Proc),
              via: 'get',
              as: 'health',
              route_alias: 'health'
            )
          end
        end

        context 'when the route is not a health check' do
          it 'registers the route with authentication' do
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

        context 'when the route raises a NotFoundError' do
          subject(:not_found_route) { TestNotFoundRoute.new('/not-found', 'get', 'not_found_route') }

          it 'returns a JSON error response with 404 status' do
            handler_proc = nil

            # Capture the handler proc that's passed to match
            allow(rails_router).to receive(:match) do |_url, **opts|
              handler_proc = opts[:to]
            end

            not_found_route.send(:register_rails, rails_router)

            # Call the handler with a mock request
            mock_env = {}
            allow(middleware).to receive(:call).and_return([200, { caller: 'test' }, ['OK']])

            status, headers, body = handler_proc.call(mock_env)

            expect(status).to eq(404)
            expect(headers['Content-Type']).to eq('application/json')
            expect(headers['x-error-type']).to eq('object-not-found')

            parsed_body = JSON.parse(body[0])
            expect(parsed_body).to have_key('errors')
            expect(parsed_body['errors']).to be_an(Array)
            expect(parsed_body['errors'][0]['name']).to eq('NotFoundError')
            expect(parsed_body['errors'][0]['detail']).to eq('Resource not found')
            expect(parsed_body['errors'][0]['status']).to eq(404)
          end
        end
      end
    end
  end
end
