require 'spec_helper'
require 'rails'
require 'action_dispatch'
require 'active_support/core_ext/hash/indifferent_access'

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

    # Test route that returns a binary payload — emulates an action File result.
    # The "%\xE2\xE3\xCF\xD3" prefix forces non-UTF8 bytes (the PDF binary marker),
    # which is exactly what used to crash serialize_response.
    class BinaryTestRoute < BaseRoute
      def handle_request(_args)
        {
          status: 200,
          headers: { 'Content-Type' => 'application/pdf' },
          content: String.new("%PDF-1.4\n%\xE2\xE3\xCF\xD3\nbinary-body-bytes", encoding: 'ASCII-8BIT'),
          raw: true
        }
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

        context 'when the app is an ActionDispatch::Routing::Mapper and Sinatra is defined' do
          let(:rails_app) { Class.new(Rails::Application) }
          let(:rails_router) { ActionDispatch::Routing::Mapper.new(rails_app.routes) }

          before do
            stub_const('Sinatra::Base', Class.new)
            allow(route).to receive(:register_rails)
          end

          it 'calls register_rails without raising NoMethodError' do
            expect { route.registered(rails_router) }.not_to raise_error
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

        # Integration: exercises the handler proc that register_rails passes
        # to router.match. This is the only place where binary action results
        # actually hit Rack — unit tests that stub collection.execute return a
        # Ruby Hash that never goes through serialize_response.
        context 'when the handler returns a raw binary response (File action)' do
          subject(:binary_route) { BinaryTestRoute.new('/binary', 'post', 'binary_test') }
          let(:expected_bytes) do
            String.new("%PDF-1.4\n%\xE2\xE3\xCF\xD3\nbinary-body-bytes", encoding: 'ASCII-8BIT')
          end
          let(:request) do
            instance_double(
              ActionDispatch::Request,
              path_parameters: {}, query_parameters: {}, request_parameters: {}, env: {}
            )
          end

          it 'passes the binary body to Rack untouched (no JSON encoding)' do
            captured_handler = nil
            allow(rails_router).to receive(:match) { |_, opts| captured_handler = opts[:to] }
            binary_route.send(:register_rails, rails_router)

            env = {
              'REQUEST_METHOD' => 'POST',
              'PATH_INFO' => '/binary',
              'QUERY_STRING' => '',
              'rack.input' => StringIO.new
            }
            status, response_headers, body = captured_handler.call(env)

            expect(status).to eq(200)
            expect(response_headers['Content-Type']).to eq('application/pdf')
            expect(body).to be_an(Array)
            expect(body.first).to eq(expected_bytes)
            expect(body.first.encoding.name).to eq('ASCII-8BIT')
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

          it 'passes raw binary content through without JSON-encoding it (e.g. File action result)' do
            binary = String.new("%PDF-1.4\n%\xE2\xE3\xCF\xD3\n", encoding: 'ASCII-8BIT')
            result = {
              status: 200,
              headers: { 'Content-Type' => 'application/pdf' },
              content: binary,
              raw: true
            }

            response = route.send(:build_rails_response, result)

            expect(response[0]).to eq(200)
            expect(response[1]['Content-Type']).to eq('application/pdf')
            expect(response[2]).to eq([binary])
            expect(response[2].first.encoding.name).to eq('ASCII-8BIT')
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

      describe '#extract_request_params' do
        let(:request) do
          instance_double(
            ActionDispatch::Request,
            path_parameters: { controller: 'forest_admin_rails/forest', action: 'index',
                               format: 'json', collection_name: 'books' },
            query_parameters: { 'page' => '2' },
            request_parameters: { 'filter' => { 'search' => 'hello' } }
          )
        end

        it 'merges path, query and body params with indifferent access' do
          params = route.send(:extract_request_params, request)

          expect(params['collection_name']).to eq('books')
          expect(params[:collection_name]).to eq('books')
          expect(params['page']).to eq('2')
          expect(params['filter']['search']).to eq('hello')
        end

        it 'strips Rails-internal path keys (controller, action, format)' do
          params = route.send(:extract_request_params, request)

          expect(params).not_to have_key('controller')
          expect(params).not_to have_key('action')
          expect(params).not_to have_key('format')
        end

        it 'lets body params override path params on key collision' do
          allow(request).to receive_messages(
            path_parameters: { collection_name: 'from_path' },
            query_parameters: {},
            request_parameters: { 'collection_name' => 'from_body' }
          )

          expect(route.send(:extract_request_params, request)['collection_name']).to eq('from_body')
        end
      end
    end
  end
end
