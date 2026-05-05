require 'spec_helper'
require 'faraday'

module ForestAdminAgent
  module Routes
    module Workflow
      describe WorkflowExecutorProxy do
        include_context 'with caller'

        subject(:proxy) { described_class.new }

        let(:executor_url) { 'http://workflow-executor.test:4001' }
        let(:run_id) { 'run_abc123' }
        let(:headers) do
          {
            'HTTP_AUTHORIZATION' => bearer,
            'Authorization' => bearer,
            'Cookie' => 'forest_session_token=abc',
            'forest-secret-key' => 'should-not-be-forwarded'
          }
        end

        # Capture-based Faraday stubbing: store the request that hit `run_request`
        # so each test can assert exact url/method/body/headers/params.
        let(:captured) { {} }
        let(:fake_response) do
          instance_double(
            Faraday::Response,
            status: 200,
            body: { 'id' => run_id, 'state' => 'pending' },
            headers: { 'content-type' => 'application/json' }
          )
        end

        def override_config(extra)
          container = ForestAdminAgent::Builder::AgentFactory.instance.container
          existing = container.resolve(:config)
          container._container.delete('config')
          container.register(:config, existing.merge(extra))
        end

        before do
          override_config(workflow_executor_url: executor_url)

          # Skip the real JWT/permissions resolution: we test proxy behavior, not
          # the auth chain itself (covered by AbstractAuthenticatedRoute specs).
          allow(proxy).to receive(:build).and_return(nil)

          faraday_request_class = Struct.new(:params)
          captured_state = captured
          response_for_request = fake_response

          allow(Faraday).to receive(:new).and_wrap_original do |original, *args, &block|
            connection = original.call(*args, &block)
            allow(connection).to receive(:run_request) do |method, url, body, hdrs, &req_block|
              captured_params = {}
              req_block&.call(faraday_request_class.new(captured_params))
              captured_state.merge!(
                method: method,
                url: url,
                body: body,
                headers: hdrs,
                query: captured_params.dup
              )
              response_for_request
            end
            connection
          end
        end

        describe '#setup_routes' do
          it 'registers the GET /_internal/workflow-executions/:run_id route' do
            proxy.setup_routes
            route = proxy.routes['forest_workflow_run_show']
            expect(route).to include(
              method: 'get',
              uri: '/_internal/workflow-executions/:run_id'
            )
          end

          it 'registers the POST /_internal/workflow-executions/:run_id/trigger route' do
            proxy.setup_routes
            route = proxy.routes['forest_workflow_run_trigger']
            expect(route).to include(
              method: 'post',
              uri: '/_internal/workflow-executions/:run_id/trigger'
            )
          end

          context 'when workflow_executor_url is nil' do
            before { override_config(workflow_executor_url: nil) }

            it 'does not register any route (so they are absent from rails routes)' do
              expect(described_class.new.routes).to be_empty
            end
          end

          context 'when workflow_executor_url is blank' do
            before { override_config(workflow_executor_url: '   ') }

            it 'does not register any route' do
              expect(described_class.new.routes).to be_empty
            end
          end
        end

        describe '#handle_request (GET)' do
          let(:args) do
            {
              headers: headers,
              params: { 'run_id' => run_id, 'page' => '2', 'route_alias' => 'forest_workflow_run_show' }
            }
          end

          it 'forwards GET to the executor /runs/:run_id path' do
            proxy.handle_request(:get, args)
            expect(captured[:method]).to eq(:get)
            expect(captured[:url]).to eq("#{executor_url}/runs/#{run_id}")
          end

          it 'forwards client query params and drops Rails routing keys' do
            proxy.handle_request(:get, args)
            expect(captured[:query]).to eq('page' => '2')
          end

          it 'forwards only Authorization and Cookie headers' do
            proxy.handle_request(:get, args)
            expect(captured[:headers]).to eq(
              'Authorization' => bearer,
              'Cookie' => 'forest_session_token=abc'
            )
          end

          it 'returns the executor status, body and Content-Type to the controller' do
            result = proxy.handle_request(:get, args)
            expect(result).to eq(
              content: { 'id' => run_id, 'state' => 'pending' },
              status: 200,
              headers: { 'Content-Type' => 'application/json' }
            )
          end
        end

        describe '#handle_request (POST trigger)' do
          let(:args) do
            {
              headers: headers,
              params: {
                'run_id' => run_id,
                'data' => { 'step' => 'approve', 'value' => 42 }
              }
            }
          end

          it 'forwards POST to the executor /runs/:run_id/trigger path with the JSON body' do
            proxy.handle_request(:post, args)
            expect(captured[:method]).to eq(:post)
            expect(captured[:url]).to eq("#{executor_url}/runs/#{run_id}/trigger")
            expect(captured[:body]).to eq('step' => 'approve', 'value' => 42)
          end
        end

        describe 'when workflow_executor_url is not configured' do
          before do
            override_config(workflow_executor_url: nil)
          end

          it 'raises NotFoundError so the controller renders 404' do
            expect do
              proxy.handle_request(:get, headers: headers, params: { 'run_id' => run_id })
            end.to raise_error(Http::Exceptions::NotFoundError, /not configured/)
          end
        end

        describe 'when the executor is unreachable' do
          before do
            allow(Faraday).to receive(:new).and_wrap_original do |original, *args, &block|
              connection = original.call(*args, &block)
              allow(connection).to receive(:run_request).and_raise(
                Faraday::ConnectionFailed.new('boom')
              )
              connection
            end
          end

          it 'raises ServiceUnavailableError (translated to 503 by ErrorTranslator)' do
            expect do
              proxy.handle_request(:get, headers: headers, params: { 'run_id' => run_id })
            end.to raise_error(Http::Exceptions::ServiceUnavailableError, /unreachable/)
          end
        end

        describe 'when the executor times out' do
          before do
            allow(Faraday).to receive(:new).and_wrap_original do |original, *args, &block|
              connection = original.call(*args, &block)
              allow(connection).to receive(:run_request).and_raise(
                Faraday::TimeoutError.new('slow')
              )
              connection
            end
          end

          it 'raises ServiceUnavailableError' do
            expect do
              proxy.handle_request(:get, headers: headers, params: { 'run_id' => run_id })
            end.to raise_error(Http::Exceptions::ServiceUnavailableError, /timed out/)
          end
        end

        describe 'when the executor returns a non-2xx response' do
          let(:fake_response) do
            instance_double(
              Faraday::Response,
              status: 422,
              body: { 'error' => 'invalid step' },
              headers: { 'content-type' => 'application/json' }
            )
          end

          it 'forwards the status and body verbatim' do
            result = proxy.handle_request(:get, headers: headers, params: { 'run_id' => run_id })
            expect(result[:status]).to eq(422)
            expect(result[:content]).to eq('error' => 'invalid step')
          end
        end

        describe 'class hierarchy' do
          it 'inherits from AbstractAuthenticatedRoute (so JWT auth runs before forwarding)' do
            expect(described_class.ancestors).to include(AbstractAuthenticatedRoute)
          end
        end
      end
    end
  end
end
