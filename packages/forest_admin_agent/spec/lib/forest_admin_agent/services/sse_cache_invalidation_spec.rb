require 'spec_helper'
require 'ld-eventsource'

module ForestAdminAgent
  module Services
    describe SSECacheInvalidation do
      let(:sse_client) { instance_double(SSE::Client) }

      let(:permissions) { class_double(Permissions).as_stubbed_const }

      let(:sse_heartbeat) { SSE::StreamEvent.new(:heartbeat, 'heartbeat', nil) }

      let(:see_foo) { SSE::StreamEvent.new(:foo, 'foo', nil) }

      let(:sse_refresh_users) { SSE::StreamEvent.new(:'refresh-users', 'refresh-users', nil) }

      let(:sse_refresh_roles) { SSE::StreamEvent.new(:'refresh-roles', 'refresh-roles', nil) }

      let(:sse_refresh_renderings) { SSE::StreamEvent.new(:'refresh-renderings', '{"renderingIds":[47]}', nil) }

      before do
        allow(permissions).to receive(:invalidate_cache).with(any_args).and_return(nil)
      end

      it 'does nothing when it receives heartbeat event' do
        allow(SSE::Client).to receive(:new).and_yield(sse_client)
        allow(sse_client).to receive(:on_event).and_yield(sse_heartbeat)

        expect(permissions).not_to have_received(:invalidate_cache)
        described_class.run
      end

      it 'does nothing when it receives unknown sse event' do
        allow(SSE::Client).to receive(:new).and_yield(sse_client)
        allow(sse_client).to receive(:on_event).and_yield(see_foo)

        expect(permissions).not_to have_received(:invalidate_cache)
        described_class.run
      end

      it 'invalidates cache forest.users when it receives refresh-users event' do
        allow(SSE::Client).to receive(:new).and_yield(sse_client)
        allow(sse_client).to receive(:on_event).and_yield(sse_refresh_users)

        described_class.run
        expect(permissions).to have_received(:invalidate_cache).with('forest.users')
      end

      it 'invalidates cache forest.collections when it receives refresh-roles event' do
        allow(SSE::Client).to receive(:new).and_yield(sse_client)
        allow(sse_client).to receive(:on_event).and_yield(sse_refresh_roles)

        described_class.run
        expect(permissions).to have_received(:invalidate_cache).with('forest.collections')
      end

      it 'invalidates cache forest.collections when it receives refresh-renderings event' do
        allow(SSE::Client).to receive(:new).and_yield(sse_client)
        allow(sse_client).to receive(:on_event).and_yield(sse_refresh_renderings)

        described_class.run
        expect(permissions).to have_received(:invalidate_cache).with('forest.collections')
        expect(permissions).to have_received(:invalidate_cache).with('forest.stats')
        expect(permissions).to have_received(:invalidate_cache).with('forest.scopes')
      end
    end
  end
end
