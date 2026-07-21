require 'active_support/isolated_execution_state'
require 'active_support/notifications'

module ForestAdminDatasourceToolkit
  # Backend-agnostic instrumentation seam. Emits ActiveSupport::Notifications
  # events under the "*.forest_admin" namespace so host apps can subscribe and
  # forward to any monitoring stack. No-op cost when nobody subscribes.
  module Monitoring
    # Uniform entry point, callable from anywhere (decorator, utility class, plain
    # object, or a client's custom handler). Pass `caller:` to auto-merge the acting
    # user's non-PII identity (user_id/rendering_id/project) into the payload.
    def self.instrument(event, payload = {}, caller: nil, &block)
      enriched = payload.merge(caller_payload(caller)).compact
      ActiveSupport::Notifications.instrument("#{event}.forest_admin", enriched, &block)
    end

    # Non-PII identity of the acting Forest user, to merge into an event payload.
    def self.caller_payload(caller)
      return {} unless caller

      { user_id: caller.id, rendering_id: caller.rendering_id, project: caller.project }
    end
  end
end
