module ForestAdminDatasourceZendesk
  module Actions
    # No-form actions exposed on the ZendeskTicket collection that flip the
    # ticket status to `solved` or `closed`. Each target status is exposed in
    # both Single and Bulk scopes, so the actions surface from a ticket's
    # detail page *and* from a multi-selection on the index.
    #
    # Status semantics: `solved` is the standard "resolved" workflow — the
    # requester can still reopen during Zendesk's reopen window. `closed` is
    # terminal; Zendesk itself sometimes rejects the direct `open → closed`
    # transition, in which case the underlying API error bubbles up (we don't
    # silently retry via `solved`).
    #
    # Opt-in registration: neither status is registered by default. Pass
    # `close_ticket_statuses: %w[solved closed]` (or any subset) to
    # `Datasource.new` to expose the variants you want.
    module CloseTicket
      BaseAction  = ForestAdminDatasourceCustomizer::Decorators::Action::BaseAction
      ActionScope = ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope

      STATUSES = %w[solved closed].freeze

      NAMES = {
        'solved' => { single: 'Mark as solved',  bulk: 'Mark selected as solved' }.freeze,
        'closed' => { single: 'Mark as closed',  bulk: 'Mark selected as closed' }.freeze
      }.freeze

      SCOPES = { single: ActionScope::SINGLE, bulk: ActionScope::BULK }.freeze

      module_function

      def variants(statuses = STATUSES)
        unknown = statuses - STATUSES
        if unknown.any?
          raise ForestAdminDatasourceToolkit::Exceptions::ForestException,
                "Unknown close_ticket_statuses: #{unknown.join(", ")}. Allowed: #{STATUSES.join(", ")}."
        end

        statuses.flat_map do |status|
          NAMES[status].map { |scope_key, name| [name, status, SCOPES[scope_key]] }
        end
      end

      # Reads `datasource.close_ticket_statuses` by default — falls back to an
      # explicit `statuses:` kwarg if a caller wants to override (e.g. when
      # attaching CloseTicket to a different collection).
      def register_on(collection, datasource, statuses: nil)
        variants(statuses || datasource.close_ticket_statuses).each do |name, status, scope|
          collection.add_action(name, build(datasource, status: status, scope: scope))
        end
      end

      def build(datasource, status:, scope:)
        BaseAction.new(scope: scope, &executor(datasource, status))
      end

      def executor(datasource, status)
        lambda do |context, result_builder|
          ids = Array(context.record_ids).compact
          next result_builder.error(message: 'No ticket selected.') if ids.empty?

          succeeded, failed = apply_status(datasource, ids, status)
          if succeeded.empty?
            result_builder.error(message: error_message(failed, status))
          else
            result_builder.success(message: success_message(succeeded, failed, status))
          end
        end
      end

      # Walks ids one by one so a single rejected transition (e.g. Zendesk
      # refusing `open -> closed`) doesn't abort the rest of a bulk run.
      # Returns `[succeeded_ids, failures]` where `failures` is `[[id, reason], ...]`.
      def apply_status(datasource, ids, status)
        succeeded = []
        failed = []
        ids.each do |id|
          datasource.client.update_ticket(id, 'status' => status)
          succeeded << id
        rescue StandardError => e
          ForestAdminDatasourceZendesk.logger.warn(
            "[forest_admin_datasource_zendesk] failed to set ticket ##{id} to '#{status}': #{e.class}: #{e.message}"
          )
          failed << [id, "#{e.class}: #{e.message}"]
        end
        [succeeded, failed]
      end

      def success_message(succeeded, failed, status)
        verb = status == 'closed' ? 'closed' : 'marked as solved'
        base = succeeded.size == 1 ? "Ticket ##{succeeded.first} #{verb}." : "#{succeeded.size} tickets #{verb}."
        return base if failed.empty?

        "#{base} #{failed.size} failed: #{failed.map(&:first).join(", ")}."
      end

      def error_message(failed, status)
        verb = status == 'closed' ? 'close' : 'mark as solved'
        return "Failed to #{verb} ticket ##{failed.first.first}: #{failed.first.last}" if failed.size == 1

        "Failed to #{verb} all #{failed.size} tickets. First error: #{failed.first.last}"
      end
    end
  end
end
