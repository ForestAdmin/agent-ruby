module ForestAdminDatasourcePylon
  module Plugins
    # Moves the selected issues to a state, `closed` unless told otherwise.
    #
    # One variant per scope, where the Zendesk plugin builds four: Zendesk has
    # two terminal statuses to tell apart, Pylon has `closed` and, past it, the
    # custom status slugs an organization defines — which the `state` option
    # takes, rather than a second dimension of action names nobody would read.
    #
    # The state is written through the client rather than through the
    # collection: the action is registered on the host collection, which is
    # rarely PylonIssue, and going through a collection would mean resolving it
    # from a datasource the plugin was not given.
    class CloseIssue < ForestAdminDatasourceCustomizer::Plugins::Plugin
      BaseAction      = ForestAdminDatasourceCustomizer::Decorators::Action::BaseAction
      ActionScope     = ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope
      ForestException = ForestAdminDatasourceToolkit::Exceptions::ForestException

      SCOPE_KEYS = %i[single bulk].freeze
      SCOPES = { single: ActionScope::SINGLE, bulk: ActionScope::BULK }.freeze
      NAMES = { single: 'Close Pylon issue', bulk: 'Close selected Pylon issues' }.freeze
      NAME_OPTIONS = { single: :action_name, bulk: :bulk_action_name }.freeze

      def run(_datasource_customizer, collection_customizer = nil, options = {})
        opts = options.is_a?(Hash) ? options : {}
        datasource = opts[:datasource]
        raise ForestException, 'CloseIssue plugin requires :datasource' unless datasource
        raise ForestException, 'CloseIssue plugin requires a collection' unless collection_customizer

        state = normalize_state(opts[:state])

        normalize_scopes(opts[:scopes]).each do |scope_key|
          collection_customizer.add_action(name_for(scope_key, opts),
                                           build_action(datasource, SCOPES[scope_key], state, opts[:issue_id_field]))
        end
      end

      private

      # Left unchecked against `STANDARD_STATES`: Pylon takes the slug of a
      # custom status just as well, and refusing one would refuse the very
      # workflow an organization built.
      def normalize_state(value)
        state = value.nil? ? IssueEnums::CLOSED_STATE : value.to_s
        return state unless state.strip.empty?

        raise ForestException, 'CloseIssue :state cannot be empty.'
      end

      def normalize_scopes(value)
        scopes = Array(value).map(&:to_sym).uniq
        scopes = SCOPE_KEYS if scopes.empty?
        unknown = scopes - SCOPE_KEYS
        return scopes if unknown.empty?

        raise ForestException,
              "Unknown CloseIssue scopes: #{unknown.join(", ")}. Allowed: #{SCOPE_KEYS.join(", ")}."
      end

      def name_for(scope_key, opts)
        opts[NAME_OPTIONS[scope_key]] || NAMES[scope_key]
      end

      def build_action(datasource, scope, state, issue_id_field)
        BaseAction.new(scope: scope, &executor(datasource, state, issue_id_field))
      end

      def executor(datasource, state, issue_id_field)
        lambda do |context, result_builder|
          ids = IssueTargets.resolve_issue_ids(context, issue_id_field)
          next result_builder.error(message: Messages.no_target(issue_id_field)) if ids.empty?

          succeeded, failed = apply_state(datasource, ids, state)
          next result_builder.error(message: Messages.error(failed, state)) if succeeded.empty?

          result_builder.success(message: Messages.success(succeeded, failed, state))
        end
      end

      # One rescue per id: a single issue Pylon refuses — deleted, or outside
      # the token's scope — must not cost the operator the rest of a selection,
      # and what failed is named in the message rather than left to a log.
      def apply_state(datasource, ids, state)
        succeeded = []
        failed = []

        ids.each do |id|
          datasource.client.update_issue(id, 'state' => state)
          succeeded << id
        rescue StandardError => e
          ForestAdminDatasourcePylon.logger.warn(
            "[forest_admin_datasource_pylon] failed to move issue #{id} to '#{state}': #{e.class}: #{e.message}"
          )
          failed << [id, "#{e.class}: #{e.message}"]
        end

        [succeeded, failed]
      end
    end
  end
end
