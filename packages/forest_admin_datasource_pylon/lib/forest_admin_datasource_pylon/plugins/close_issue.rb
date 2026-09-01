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

      # What one run may write, the budget a filter-driven write already gets:
      # this writes one PATCH per issue too, sequentially, and the action runs
      # inside a single HTTP request. Past this the batch is refused before the
      # first write rather than discovered after the twentieth, where a run cut
      # short by a timeout leaves part of the selection moved and reports which
      # part to nobody -- `apply_state` only names it once the loop returns.
      #
      # The collection cannot bound this: the action writes through the client,
      # being registered on the host collection rather than on PylonIssue.
      MAX_TARGETS = Collections::Writes::MAX_WRITE_REQUESTS

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

        names = normalize_scopes(opts[:scopes]).to_h { |scope_key| [scope_key, name_for(scope_key, opts)] }
        refuse_colliding_names(names)

        names.each do |scope_key, name|
          collection_customizer.add_action(name,
                                           build_action(datasource, SCOPES[scope_key], state, opts[:issue_id_field]))
        end
      end

      private

      # Left unchecked against the states Pylon ships: it takes the slug of a
      # custom status just as well, and refusing one would refuse the very
      # workflow an organization built.
      def normalize_state(value)
        state = value.nil? ? IssueEnums::CLOSED_STATE : value.to_s.strip
        return state unless state.empty?

        raise ForestException, 'CloseIssue :state cannot be empty.'
      end

      # Through `to_s`: a value that is neither a string nor a symbol has no
      # `to_sym`, and raising NoMethodError here would hide the unknown-scope
      # error that names what was actually passed.
      def normalize_scopes(value)
        scopes = Array(value).map { |scope| scope.to_s.to_sym }.uniq
        scopes = SCOPE_KEYS if scopes.empty?
        unknown = scopes - SCOPE_KEYS
        return scopes if unknown.empty?

        raise ForestException,
              "Unknown CloseIssue scopes: #{unknown.join(", ")}. Allowed: #{SCOPE_KEYS.join(", ")}."
      end

      # Through `to_s`, like the scopes: an action registers under the name it is
      # given, and a Symbol reaching the schema breaks the agent rather than the
      # action -- `GeneratorAction.get_action_slug` calls `strip` on it, and
      # `GeneratorCollection` sorts the names of a collection's actions, which
      # raises as soon as a Symbol sits beside a String. It also makes
      # `:Resolve` and `'Resolve'` the one name they read as.
      def name_for(scope_key, opts)
        (opts[NAME_OPTIONS[scope_key]] || NAMES[scope_key]).to_s
      end

      # `add_action` keys a collection's actions by name, so two variants sharing
      # one leave the second overwriting the first: the single-record action
      # disappears from the panel and what stays answers with the other scope --
      # a bulk action offered on one record, or the reverse. Refused at
      # registration, like the other configurations this plugin will not perform
      # quietly.
      def refuse_colliding_names(names)
        collision = names.values.tally.find { |_name, count| count > 1 }
        return if collision.nil?

        raise ForestException,
              "CloseIssue registers one action per scope, and #{names.keys.join(" and ")} both resolve to " \
              "'#{collision.first}'. Give :action_name and :bulk_action_name different values, or register " \
              'a single scope.'
      end

      def build_action(datasource, scope, state, issue_id_field)
        BaseAction.new(scope: scope, &executor(datasource, state, issue_id_field))
      end

      def executor(datasource, state, issue_id_field)
        lambda do |context, result_builder|
          ids = IssueTargets.resolve_issue_ids(context, issue_id_field)
          next result_builder.error(message: Messages.no_target(issue_id_field)) if ids.empty?
          next result_builder.error(message: Messages.too_many(ids.size, state)) if ids.size > MAX_TARGETS

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
