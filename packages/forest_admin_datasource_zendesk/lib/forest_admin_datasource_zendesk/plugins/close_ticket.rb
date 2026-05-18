module ForestAdminDatasourceZendesk
  module Plugins
    # The Zendesk ticket id is read from a configurable column on the host
    # record(s); Zendesk sometimes rejects the direct `open -> closed`
    # transition so failures are surfaced per-id rather than retried.
    class CloseTicket < ForestAdminDatasourceCustomizer::Plugins::Plugin
      BaseAction      = ForestAdminDatasourceCustomizer::Decorators::Action::BaseAction
      ActionScope     = ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope
      ForestException = ForestAdminDatasourceToolkit::Exceptions::ForestException

      STATUSES = %w[solved closed].freeze
      SCOPE_KEYS = %i[single bulk].freeze

      NAMES = {
        'solved' => { single: 'Mark Zendesk ticket as solved',
                      bulk: 'Mark selected Zendesk tickets as solved' }.freeze,
        'closed' => { single: 'Mark Zendesk ticket as closed',
                      bulk: 'Mark selected Zendesk tickets as closed' }.freeze
      }.freeze

      SCOPES = { single: ActionScope::SINGLE, bulk: ActionScope::BULK }.freeze

      def run(_datasource_customizer, collection_customizer = nil, options = {})
        datasource = options[:datasource]
        ticket_id_field = options[:ticket_id_field]
        raise ForestException, 'CloseTicket plugin requires :datasource' unless datasource
        raise ForestException, 'CloseTicket plugin requires :ticket_id_field' unless ticket_id_field
        raise ForestException, 'CloseTicket plugin requires a collection' unless collection_customizer

        statuses = normalize_statuses(options[:statuses])
        scopes   = normalize_scopes(options[:scopes])

        variants(statuses, scopes).each do |name, status, scope|
          collection_customizer.add_action(name, build_action(datasource, status, scope, ticket_id_field))
        end
      end

      private

      def normalize_statuses(value)
        normalize(value, :to_s, STATUSES, 'statuses')
      end

      def normalize_scopes(value)
        normalize(value, :to_sym, SCOPE_KEYS, 'scopes')
      end

      def normalize(value, cast, allowed, label)
        list = Array(value).map(&cast).uniq
        list = allowed if list.empty?
        unknown = list - allowed
        return list if unknown.empty?

        raise ForestException,
              "Unknown CloseTicket #{label}: #{unknown.join(", ")}. Allowed: #{allowed.join(", ")}."
      end

      def variants(statuses, scopes)
        statuses.flat_map do |status|
          scopes.map { |scope_key| [NAMES[status][scope_key], status, SCOPES[scope_key]] }
        end
      end

      def build_action(datasource, status, scope, ticket_id_field)
        BaseAction.new(scope: scope, &executor(datasource, status, ticket_id_field))
      end

      def executor(datasource, status, ticket_id_field)
        lambda do |context, result_builder|
          ids = resolve_ticket_ids(context, ticket_id_field)
          next result_builder.error(message: "No Zendesk ticket id found in '#{ticket_id_field}'.") if ids.empty?

          succeeded, already_closed, failed = apply_status(datasource, ids, status)

          # Closed tickets can't be reopened to 'solved'; fold into failures.
          if status == 'solved'
            failed += already_closed.map { |id| [id, 'ticket is already closed (cannot reopen to mark as solved)'] }
            already_closed = []
          end

          if succeeded.empty? && already_closed.empty?
            result_builder.error(message: Messages.error(failed, status))
          else
            result_builder.success(message: Messages.success(succeeded, already_closed, failed, status))
          end
        end
      end

      def resolve_ticket_ids(context, ticket_id_field)
        records = context.get_records([ticket_id_field])
        records.filter_map { |r| r[ticket_id_field.to_s] }
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
        already_closed = []
        failed = []
        ids.each do |id|
          datasource.client.update_ticket(id, 'status' => status)
          succeeded << id
        rescue StandardError => e
          if Errors.already_closed?(e)
            already_closed << id
          else
            ForestAdminDatasourceZendesk.logger.warn(
              "[forest_admin_datasource_zendesk] failed to set ticket ##{id} to '#{status}': " \
              "#{e.class}: #{e.message}"
            )
            failed << [id, "#{e.class}: #{e.message}"]
          end
        end
        [succeeded, already_closed, failed]
      end
    end
  end
end
