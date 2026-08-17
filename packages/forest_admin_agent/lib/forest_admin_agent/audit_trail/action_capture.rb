require 'uri'

module ForestAdminAgent
  module AuditTrail
    # Records smart-action runs into the same table as the field-level history: the submitted form on the
    # `previous_values` side, what the action answered on the `new_values` side.
    #
    # {Capture} cannot see them — the customizer has no `Execute` hook — and an action's writes are only
    # audited when they go through the Forest data layer, so a direct ORM write stays invisible. What lands
    # here is the run itself: who ran which action, on which records, with which form, and how it ended.
    #
    # Same protocol as a write: {#pending} before the action, {#confirm} after. The route owns the gate, so a
    # pending insert that fails refuses the run under `critical: true`.
    class ActionCapture
      include Recording

      EXECUTED = 'action'.freeze
      FAILED = 'action_failed'.freeze
      # A global action, and a bulk run over a selection wider than the cap, name no single target: they get
      # one row attached to no record rather than none at all.
      NO_RECORD = ''.freeze
      # What of the action's answer is worth keeping — an allowlist, not a denylist: a result also carries the
      # file's contents, a webhook's body and headers and arbitrary response headers. File bytes have no
      # business in an audit table and the other two routinely hold credentials, and an allowlist means a field
      # added to a result later is not stored until someone decides it should be. `html` is left out too:
      # operator-facing markup, sometimes large, and the message already says what happened.
      RESULT_FIELDS = %i[type message name mime_type method url path].freeze
      # Either can carry userinfo credentials or a signed one-time token, which would then sit permanently in
      # the one table nobody deletes from.
      URL_FIELDS = %i[url path].freeze

      def initialize(store, redact = {})
        @store = store
        @redact = redact || {}
      end

      # One row per targeted record, provisionally an `action` — {#confirm} settles which it really was. Returns
      # the row ids to confirm.
      def pending(caller:, collection:, action_name:, form_values:, record_ids:)
        return [] unless @store

        timestamp = now
        correlation_key = correlation_key_for(caller)
        identity = identity_of(caller)
        submitted = redact(form_values || {}, @redact[collection] || [])
        ids = record_ids.empty? ? [NO_RECORD] : record_ids

        @store.append_all(
          ids.map do |record_id|
            AuditRecord.new(
              timestamp: timestamp, operation: EXECUTED, collection: collection, record_id: record_id,
              status: PENDING, action_name: action_name, correlation_key: correlation_key,
              previous_values: submitted, new_values: {}, **identity
            )
          end
        )
      end

      # Best-effort: the action has already run, so a failure here loses the answer, never the run.
      def confirm(ids, result: nil, failed: false)
        return if ids.nil? || ids.empty?

        audit_safely do
          answer = summarize(result)

          ids.each { |id| @store.confirm(id, operation: failed ? FAILED : EXECUTED, new_values: answer) }
        end
      end

      private

      # Keys of an action's answer are Forest's own, so they are camelCase on the wire — unlike a record's
      # column names, which pass through untouched.
      def summarize(result)
        return {} unless result.is_a?(Hash)

        result.slice(*RESULT_FIELDS).compact.to_h do |field, value|
          [field.to_s.camelize(:lower), URL_FIELDS.include?(field) ? sanitize_url(value) : value]
        end
      end

      # `userinfo = nil` is a no-op on URI, so the credentials come off textually; the parser then takes care
      # of the query and fragment.
      def sanitize_url(value)
        bare = value.to_s.sub(%r{\A([a-z][a-z0-9+.-]*://)[^/@]*@}i, '\1')
        uri = URI.parse(bare)
        uri.query = nil
        uri.fragment = nil

        uri.to_s
      rescue StandardError
        # Not something the parser accepts: keep the shape, drop everything that can carry a secret.
        bare.to_s.split(/[?#]/).first.to_s
      end
    end
  end
end
