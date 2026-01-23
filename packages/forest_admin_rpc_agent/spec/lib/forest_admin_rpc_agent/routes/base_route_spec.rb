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
      end

      describe '#build_rails_response' do
        context 'when result is a Hash with :status key' do
          it 'returns the correct response structure' do
            result = { status: 201, content: { id: 1 } }
            response = route.send(:build_rails_response, result)

            expect(response[0]).to eq(201)
            expect(response[1]).to eq({ 'Content-Type' => 'application/json' })
            expect(response[2]).to eq(['{"id":1}'])
          end

          it 'merges custom headers when provided' do
            result = { status: 200, content: { data: 'test' }, headers: { 'X-Custom-Header' => 'value' } }
            response = route.send(:build_rails_response, result)

            expect(response[0]).to eq(200)
            expect(response[1]).to eq({ 'Content-Type' => 'application/json', 'X-Custom-Header' => 'value' })
            expect(response[2]).to eq(['{"data":"test"}'])
          end

          it 'returns empty body when content is nil' do
            result = { status: 204 }
            response = route.send(:build_rails_response, result)

            expect(response[0]).to eq(204)
            expect(response[1]).to eq({ 'Content-Type' => 'application/json' })
            expect(response[2]).to eq([''])
          end
        end

        context 'when result is not a Hash with :status key' do
          it 'returns 200 with serialized result' do
            result = { test: 'data' }
            response = route.send(:build_rails_response, result)

            expect(response[0]).to eq(200)
            expect(response[1]).to eq({ 'Content-Type' => 'application/json' })
            expect(response[2]).to eq(['{"test":"data"}'])
          end
        end
      end
    end
  end
end
