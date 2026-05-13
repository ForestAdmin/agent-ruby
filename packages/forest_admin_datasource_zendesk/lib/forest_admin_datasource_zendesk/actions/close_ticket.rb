module ForestAdminDatasourceZendesk
  module Actions
    # Zendesk sometimes rejects the direct `open -> closed` transition; we
    # surface the API error per-id rather than retrying via `solved`. The
    # action is registered on an arbitrary host collection — the Zendesk
    # ticket id is read from a configurable column (`ticket_id_field`) on
    # the host record(s).
    module CloseTicket
      BaseAction  = ForestAdminDatasourceCustomizer::Decorators::Action::BaseAction
      ActionScope = ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope

      STATUSES = %w[solved closed].freeze

      NAMES = {
        'solved' => { single: 'Mark Zendesk ticket as solved',
                      bulk: 'Mark selected Zendesk tickets as solved' }.freeze,
        'closed' => { single: 'Mark Zendesk ticket as closed',
                      bulk: 'Mark selected Zendesk tickets as closed' }.freeze
      }.freeze

      SCOPES = { single: ActionScope::SINGLE, bulk: ActionScope::BULK }.freeze

      module_function

      def variants(statuses = STATUSES)
        unknown = statuses - STATUSES
        if unknown.any?
          raise ForestAdminDatasourceToolkit::Exceptions::ForestException,
                "Unknown CloseTicket statuses: #{unknown.join(", ")}. Allowed: #{STATUSES.join(", ")}."
        end

        statuses.flat_map do |status|
          NAMES[status].map { |scope_key, name| [name, status, SCOPES[scope_key]] }
        end
      end

      def register_on(collection, datasource, ticket_id_field:, statuses: nil)
        variants(statuses || STATUSES).each do |name, status, scope|
          collection.add_action(name, build(datasource, status: status, scope: scope, ticket_id_field: ticket_id_field))
        end
      end

      def build(datasource, status:, scope:, ticket_id_field:)
        BaseAction.new(scope: scope, &executor(datasource, status, ticket_id_field))
      end

      def executor(datasource, status, ticket_id_field)
        lambda do |context, result_builder|
          ids = resolve_ticket_ids(context, ticket_id_field)
          next result_builder.error(message: "No Zendesk ticket id found in '#{ticket_id_field}'.") if ids.empty?

          succeeded, failed = apply_status(datasource, ids, status)
          if succeeded.empty?
            result_builder.error(message: error_message(failed, status))
          else
            result_builder.success(message: success_message(succeeded, failed, status))
          end
        end
      end

      # Reads the host record(s) and extracts the Zendesk ticket id from the
      # configured field. Falls back to context.record_ids only when the
      # host collection is itself the Zendesk Ticket collection (in which
      # case ticket_id_field == 'id' is the canonical setup).
      def resolve_ticket_ids(context, ticket_id_field)
        records = context.get_records([ticket_id_field])
        records = [records].compact unless records.is_a?(Array)
        records.filter_map { |r| r[ticket_id_field] || r[ticket_id_field.to_sym] }
      rescue StandardError => e
        ForestAdminDatasourceZendesk.logger.warn(
          "[forest_admin_datasource_zendesk] failed to resolve ticket ids from '#{ticket_id_field}': " \
          "#{e.class}: #{e.message}"
        )
        []
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
