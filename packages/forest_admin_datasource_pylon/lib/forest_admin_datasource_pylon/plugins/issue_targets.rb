module ForestAdminDatasourcePylon
  module Plugins
    # Which Pylon issues an action was fired on.
    #
    # Two shapes, one option: `issue_id_field` names a column of the host
    # collection holding a Pylon issue id — a business collection keeping the
    # issue it opened — and, left out, the ids are the primary keys of the
    # selected records, which is what an action registered on PylonIssue itself
    # acts on.
    module IssueTargets
      module_function

      # A collection whose column was renamed, or a record the scope hides,
      # answers "no issue selected" through the action's own message rather than
      # through a stack trace in the panel.
      #
      # A ValidationError is the exception: it is the datasource refusing the
      # selection in words written for the operator — PylonIssue naming more
      # issues by id than one page of lookups covers, for one — and the agent
      # surfaces its message as it is. Swallowed, it would reach them as "no
      # issue selected" about a selection they can see they made, which is the
      # one thing the message must not say.
      def resolve_issue_ids(context, field = nil)
        ids = field.nil? ? primary_key_ids(context) : column_ids(context, field)
        # Deduplicated: a column of issue ids is not a key, so two selected
        # records may name the same issue, which would then be written twice and
        # counted twice in what the action reports back.
        ids.filter_map do |id|
          id.to_s unless id.nil? || id.to_s.empty?
        end.uniq
      rescue ForestAdminDatasourceToolkit::Exceptions::ValidationError
        raise
      rescue StandardError => e
        source = field ? "from '#{field}'" : 'from the selected records'
        ForestAdminDatasourcePylon.logger.warn(
          "[forest_admin_datasource_pylon] failed to resolve the issues to act on #{source}: " \
          "#{e.class}: #{e.message}"
        )
        []
      end

      def primary_key_ids(context)
        Array(context.get_record_ids)
      end

      def column_ids(context, field)
        context.get_records([field.to_s]).map { |record| record[field.to_s] }
      end
    end
  end
end
