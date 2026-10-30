module ForestAdminDatasourcePylon
  module Plugins
    class ReplyToIssue
      # The issue an action targets and the reply target its thread resolves to,
      # or why neither could be had. `error` set means `target` is not.
      module ThreadLookup
        State = Struct.new(:issue_id, :target, :error, keyword_init: true)

        module_function

        def call(datasource, context, opts)
          issue_id = issue_id(context, opts)
          return State.new(error: no_issue(opts[:issue_id_field])) if issue_id.nil?

          read(datasource, issue_id, opts)
        end

        def issue_id(context, opts)
          IssueTargets.resolve_issue_ids(context, opts[:issue_id_field]).first
        end

        def read(datasource, issue_id, opts)
          messages = datasource.client.fetch_complete_issue_messages(issue_id)
          State.new(issue_id: issue_id,
                    target: ReplyTarget.resolve(messages, support_emails: opts[:support_emails]))
        rescue APIError => e
          State.new(issue_id: issue_id, error: "Could not read the conversation of Pylon issue #{issue_id}: " \
                                               "#{e.message}")
        end

        def no_issue(field)
          field.nil? ? 'No Pylon issue selected.' : "No Pylon issue id found in '#{field}'."
        end
      end
    end
  end
end
