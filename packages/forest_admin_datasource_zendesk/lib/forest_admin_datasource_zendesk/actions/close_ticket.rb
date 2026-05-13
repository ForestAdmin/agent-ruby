module ForestAdminDatasourceZendesk
  module Actions
    # Zendesk sometimes rejects the direct `open -> closed` transition; we
    # surface the API error per-id rather than retrying via `solved`.
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

      # Per-id rescue so a single transition rejection doesn't abort bulk.
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
