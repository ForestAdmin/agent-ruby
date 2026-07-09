require 'active_support/isolated_execution_state'
require 'active_support/notifications'

module ForestAdminDatasourceToolkit
  # Backend-agnostic instrumentation seam. Emits ActiveSupport::Notifications
  # events under the "*.forest_admin" namespace so host apps can subscribe and
  # forward to any monitoring stack. No-op cost when nobody subscribes.
  module Monitoring
    def self.instrument(event, payload = {}, &block)
      ActiveSupport::Notifications.instrument("#{event}.forest_admin", payload.compact, &block)
    end

    # Non-PII identity of the acting Forest user, to merge into an event payload.
    def self.caller_payload(caller)
      return {} unless caller

      { user_id: caller.id, rendering_id: caller.rendering_id, project: caller.project }
    end
  end
end
