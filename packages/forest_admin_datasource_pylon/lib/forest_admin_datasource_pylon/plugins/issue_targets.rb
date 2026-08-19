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

      # Never raises: a collection whose column was renamed, or a record the
      # scope hides, answers "no issue selected" through the action's own
      # message rather than through a stack trace in the panel.
      def resolve_issue_ids(context, field = nil)
        ids = field.nil? ? primary_key_ids(context) : column_ids(context, field)
        ids.filter_map do |id|
          id.to_s unless id.nil? || id.to_s.empty?
        end
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
