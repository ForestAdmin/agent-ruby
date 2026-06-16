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
        # Rack env shape: HTTP_* (+ CONTENT_*) are headers; the rest is rack/server internals.
        let(:headers) do
          {
            'HTTP_AUTHORIZATION' => bearer,
            'HTTP_COOKIE' => 'forest_session_token=abc',
            'HTTP_X_CUSTOM_HEADER' => 'custom-value',
            'CONTENT_TYPE' => 'application/json',
            'CONTENT_LENGTH' => '123',
            'HTTP_CONNECTION' => 'keep-alive',
            'HTTP_HOST' => 'agent.test',
            'action_dispatch.remote_ip' => '127.0.0.1',
            'rack.input' => 'raw-body'
          }
        end

        # Capture-based Faraday stubbing: store the request that hit `run_request`
        # so each test can assert exact url/method/body/headers.
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

          captured_state = captured
          response_for_request = fake_response

          allow(Faraday).to receive(:new).and_wrap_original do |original, *args, &block|
            captured_state[:faraday_options] = args.first
            connection = original.call(*args, &block)
            allow(connection).to receive(:run_request) do |method, url, body, hdrs|
              captured_state.merge!(method: method, url: url, body: body, headers: hdrs)
              response_for_request
            end
            connection
          end
        end

        describe '#setup_routes' do
          it 'registers a single catch-all route forwarding every verb' do
            proxy.setup_routes
            route = proxy.routes['forest_workflow_executor_proxy']
            expect(route).to include(
              method: :all,
              uri: '/_internal/workflow-executions/*path'
            )
          end

          it 'registers exactly one route (generic — no per-executor-route entry)' do
            proxy.setup_routes
            expect(proxy.routes.keys).to eq(['forest_workflow_executor_proxy'])
          end

          context 'when workflow_executor_url is nil' do
            before { override_config(workflow_executor_url: nil) }

            it 'does not register any route' do
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

        describe '#handle_request — generic forwarding' do
          it 'forwards a GET under /runs, preserving the sub-path and query verbatim' do
            proxy.handle_request(
              method: 'GET',
              headers: headers,
              params: { 'path' => run_id },
              query_string: 'page=2&q=foo'
            )

            expect(captured[:method]).to eq(:get)
            expect(captured[:url]).to eq("#{executor_url}/runs/#{run_id}?page=2&q=foo")
            expect(captured[:body]).to be_nil
          end

          it 'forwards a POST with the raw body untouched (no reshaping)' do
            raw = '{"pendingData":{"step":"approve","value":42}}'

            proxy.handle_request(
              method: 'POST',
              headers: headers,
              params: { 'path' => "#{run_id}/trigger" },
              body: raw
            )

            expect(captured[:method]).to eq(:post)
            expect(captured[:url]).to eq("#{executor_url}/runs/#{run_id}/trigger")
            expect(captured[:body]).to eq(raw)
          end

          it 'forwards any verb and any future sub-path without a dedicated route' do
            proxy.handle_request(
              method: 'DELETE',
              headers: headers,
              params: { 'path' => "#{run_id}/cancel" }
            )

            expect(captured[:method]).to eq(:delete)
            expect(captured[:url]).to eq("#{executor_url}/runs/#{run_id}/cancel")
          end

          it 'forwards all client headers except hop-by-hop / host / content-length' do
            proxy.handle_request(method: 'GET', headers: headers, params: { 'path' => run_id })

            expect(captured[:headers]).to eq(
              'Authorization' => bearer,
              'Cookie' => 'forest_session_token=abc',
              'X-Custom-Header' => 'custom-value',
              'Content-Type' => 'application/json'
            )
          end

          it 'returns the executor status, body and Content-Type to the controller' do
            result = proxy.handle_request(method: 'GET', headers: headers, params: { 'path' => run_id })

            expect(result).to eq(
              content: { 'id' => run_id, 'state' => 'pending' },
              status: 200,
              headers: { 'Content-Type' => 'application/json' }
            )
          end
        end

        describe 'path traversal protection (the namespace security boundary)' do
          [
            '..',
            '../mcp-oauth-credentials',
            'run_abc123/../../mcp-oauth-credentials',
            '%2e%2e/mcp-oauth-credentials',
            'run_abc123%2E%2E',
            '/runs/run_abc123',
            "run\u0000id"
          ].each do |evil_path|
            it "rejects #{evil_path.inspect} with NotFoundError and never forwards" do
              expect do
                proxy.handle_request(method: 'GET', headers: headers, params: { 'path' => evil_path })
              end.to raise_error(Http::Exceptions::NotFoundError, /Invalid workflow executor path/)

              expect(captured).to be_empty
            end
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
            result = proxy.handle_request(method: 'GET', headers: headers, params: { 'path' => run_id })

            expect(result[:status]).to eq(422)
            expect(result[:content]).to eq('error' => 'invalid step')
          end
        end

        describe 'when workflow_executor_url is not configured' do
          before { override_config(workflow_executor_url: nil) }

          it 'raises NotFoundError so the controller renders 404' do
            expect do
              proxy.handle_request(method: 'GET', headers: headers, params: { 'path' => run_id })
            end.to raise_error(Http::Exceptions::NotFoundError, /not configured/)
          end
        end

        describe 'when the executor is unreachable' do
          before do
            allow(Faraday).to receive(:new).and_wrap_original do |original, *args, &block|
              connection = original.call(*args, &block)
              allow(connection).to receive(:run_request).and_raise(Faraday::ConnectionFailed.new('boom'))
              connection
            end
          end

          it 'raises ServiceUnavailableError (translated to 503 by ErrorTranslator)' do
            expect do
              proxy.handle_request(method: 'GET', headers: headers, params: { 'path' => run_id })
            end.to raise_error(Http::Exceptions::ServiceUnavailableError, /unreachable/)
          end
        end

        describe 'when the executor times out' do
          before do
            allow(Faraday).to receive(:new).and_wrap_original do |original, *args, &block|
              connection = original.call(*args, &block)
              allow(connection).to receive(:run_request).and_raise(Faraday::TimeoutError.new('slow'))
              connection
            end
          end

          it 'raises ServiceUnavailableError' do
            expect do
              proxy.handle_request(method: 'GET', headers: headers, params: { 'path' => run_id })
            end.to raise_error(Http::Exceptions::ServiceUnavailableError, /timed out/)
          end
        end

        describe 'Faraday timeout' do
          it 'applies a single large timeout regardless of the verb' do
            proxy.handle_request(method: 'POST', headers: headers, params: { 'path' => "#{run_id}/trigger" }, body: '{}')

            expect(captured[:faraday_options]).to eq(request: { open_timeout: 2, timeout: 120 })
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
