require 'filecache'
require 'deepsort'

module ForestAdminAgent
  module Services
    class Permissions
      include ForestAdminAgent::Http::Exceptions
      include ForestAdminAgent::Utils
      include ForestAdminDatasourceToolkit::Exceptions
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

      attr_reader :caller, :forest_api, :cache

      def initialize(caller)
        @caller = caller
        @forest_api = ForestAdminAgent::Http::ForestAdminApiRequester.new
        @cache = FileCache.new(
          'permissions',
          Facades::Container.config_from_cache[:cache_dir].to_s,
          Facades::Container.config_from_cache[:permission_expiration]
        )
      end

      def self.invalidate_cache(id_cache = nil)
        cache = FileCache.new(
          'permissions',
          Facades::Container.config_from_cache[:cache_dir].to_s,
          Facades::Container.config_from_cache[:permission_expiration]
        )

        cache.clear if id_cache.nil?

        cache.delete(id_cache) unless cache.get(id_cache).nil?

        ForestAdminAgent::Facades::Container.logger.log('Info', "Invalidating #{id_cache} cache..")
      end

      def can?(action, collection, allow_fetch: false)
        return true unless permission_system?

        user_data = get_user_data(caller.id)
        collections_data = get_collections_permissions_data(force_fetch: allow_fetch)

        is_allowed = permission_allowed?(collections_data, collection, action, user_data)

        unless is_allowed
          collections_data = get_collections_permissions_data(force_fetch: true)
          is_allowed = permission_allowed?(collections_data, collection, action, user_data)
        end

        raise ForbiddenError, "You don't have permission to #{action} this collection." unless is_allowed

        is_allowed
      end

      # +root_collection_name+ is pinned to readable and never looked up: +browse+ already gates a
      # listing, +read+ a get, and the signed hash a chart.
      #
      # Answered once per collection for the whole request: +redact_projection+ and
      # +assert_can_read_query_fields+ both ask on a listing, and a chart asks three times.
      def read_permissions(root_collection_name, collection_names)
        to_check = collection_names.uniq.reject { |name| name == root_collection_name }
        allowed = { root_collection_name => true }

        return allowed if to_check.empty?

        # An absent permission system is not a denial: `can?` allows everything there, and answering
        # anything else would redact every relation on a deployment that granted nothing to check.
        return allowed.merge(to_check.to_h { |name| [name, true] }) unless permission_system?

        @read_permissions ||= {}
        missing = to_check - @read_permissions.keys
        @read_permissions.merge!(fetch_read_permissions(missing)) unless missing.empty?

        allowed.merge(@read_permissions.slice(*to_check))
      end

      # An unnamed field is dropped rather than refused: the default expansion covers every column
      # of every to-one relation, so refusing would turn an ordinary listing into a 403 for a caller
      # that asked for nothing.
      def redact_projection(collection, projection, named_by_caller:)
        owners = projection.to_h do |path|
          [path, ForestAdminDatasourceToolkit::Utils::FieldPath.leaf_collection_names(collection, path)]
        end
        allowed = read_permissions(collection.name, owners.values.flatten)
        readable = ->(path) { readable_leaves?(owners[path], allowed) }

        if named_by_caller
          denied = projection.reject { |path| readable.call(path) }

          unless denied.empty?
            fields = denied.map { |path| "'#{path}' from #{leaf_label(owners[path])}" }
            raise ForbiddenError, "You are not allowed to read #{fields.join(", ")}."
          end
        end

        ForestAdminDatasourceToolkit::Components::Query::Projection.new(projection.select { |path| readable.call(path) })
      end

      # Refused rather than redacted: dropping a condition widens the result set and dropping a sort
      # clause silently reorders it, while both leak the value they touch anyway — a `starts_with`
      # filter answers one guess per request without returning a column of its own.
      #
      # The route passes the components it will actually apply, already parsed. A component it drops
      # is simply one it does not pass — a count carries no sort, a chart neither sort nor search — so
      # nothing has to be declared alongside the query and then kept in step with it. What is
      # authorised here is what the filter carries, not a second parse of the same parameters.
      def assert_can_read_query_fields(collection, condition_tree: nil, sort: nil, search: nil,
                                       search_extended: false)
        usages = []

        # `projection` collects the leaf fields without touching the tree. The route applies this very
        # instance next, so a traversal that rebuilt a branch — as `for_each_leaf` does — would leave
        # the guard deciding what runs.
        condition_tree&.projection&.each { |path| usages << usage('filter on', collection, path) }
        sort&.each { |clause| usages << usage('sort on', collection, clause[:field]) }
        collect_search_usages(collection, search, search_extended, usages)

        assert_can_read_usages(collection.name, usages)
      end

      def assert_can_read_usages(root_collection_name, usages)
        allowed = read_permissions(root_collection_name, usages.flat_map { |usage| usage[:collections] })
        denied = usages.find { |usage| !readable_leaves?(usage[:collections], allowed) }

        return unless denied

        raise ForbiddenError,
              "You cannot #{denied[:action]} '#{denied[:path]}': you are not allowed to read " \
              "#{leaf_label(denied[:collections])}."
      end

      def can_chart?(parameters)
        attributes = sanitize_chart_parameters(parameters.deep_symbolize_keys)
        hash_request = "#{attributes[:type]}:#{array_hash(attributes)}"
        is_allowed = get_chart_data(caller.rendering_id).include?(hash_request)

        is_allowed ||= get_chart_data(caller.rendering_id, force_fetch: true).include?(hash_request)

        unless is_allowed
          ForestAdminAgent::Facades::Container.logger.log(
            'Debug',
            "User #{caller.id} cannot retrieve chart on rendering #{caller.rendering_id}"
          )
          raise ForbiddenError, "You don't have permission to access this collection."
        end

        ForestAdminAgent::Facades::Container.logger.log(
          'Debug',
          "User #{caller.id} can retrieve chart on rendering #{caller.rendering_id}"
        )

        is_allowed
      end

      def can_execute_query_segment?(collection, query, connection_name)
        user_data = get_user_data(caller.id)
        if %w[admin developer editor].include?(user_data&.dig(:permissionLevel))
          ForestAdminAgent::Facades::Container.logger.log(
            'Debug',
            "User #{caller.id} can retrieve SQL segment on rendering #{caller.rendering_id}"
          )
          return true
        end

        collection_permissions = get_collection_rendering_permissions(collection, force_fetch: false)

        is_allowed = segment_permissions_valid?(collection_permissions, query, connection_name)

        unless is_allowed
          collection_permissions = get_collection_rendering_permissions(collection, force_fetch: true)
          is_allowed = segment_permissions_valid?(collection_permissions, query, connection_name)
        end

        unless is_allowed
          ForestAdminAgent::Facades::Container.logger.log(
            'Debug',
            "User #{caller.id} cannot retrieve query segment on rendering #{caller.rendering_id}"
          )

          raise ForbiddenError, "You don't have permission to use this query segment."
        end

        ForestAdminAgent::Facades::Container.logger.log(
          'Debug',
          "User #{caller.id} can retrieve query segment on rendering #{caller.rendering_id}"
        )

        is_allowed
      end

      def can_smart_action?(request, collection, filter, allow_fetch: true)
        return true unless permission_system?

        user_data = get_user_data(caller.id)
        collections_data = get_collections_permissions_data(force_fetch: allow_fetch)
        action = find_action_from_endpoint(collection.name, request[:headers]['REQUEST_PATH'], request[:headers]['REQUEST_METHOD'])

        collection_actions = validate_smart_action_permissions(collections_data, collection, action)

        smart_action_approval = SmartActionChecker.new(
          request[:params],
          collection,
          # The schema scope lets the checker skip select-all resolution for global actions.
          collection_actions[action['name'].to_sym].merge(scope: collection.schema[:actions][action['name']]&.scope),
          caller,
          user_data[:roleId],
          filter
        )

        is_allowed = smart_action_approval.can_execute?
        ForestAdminAgent::Facades::Container.logger.log(
          'Debug',
          "User #{user_data[:roleId]} is #{"not" unless is_allowed} allowed to perform #{action["name"]}"
        )

        is_allowed
      end

      def get_scope(collection)
        permissions = get_rendering_data(caller.rendering_id)
        scope = permissions[:scopes][collection.name.to_sym]

        return nil if scope.nil?

        team = get_team(caller.rendering_id)
        user = get_user_data(caller.id)

        if team.nil? || user.nil?
          raise ForestAdminDatasourceToolkit::Exceptions::ForestException,
                "Unable to resolve the caller's team or user data while computing the permission " \
                "scope for '#{collection.name}'."
        end

        context_variables = ContextVariables.new(team, user)

        ContextVariablesInjector.inject_context_in_filter(scope, context_variables)
      end

      def get_segments(collection, force_fetch: false)
        permissions = get_rendering_data(caller.rendering_id, force_fetch: force_fetch)

        permissions[:segments][collection.name.to_sym]
      end

      def get_user_data(user_id)
        cache.get_or_set('forest.users') do
          response = fetch('/liana/v4/permissions/users')
          users = {}

          response.each do |user|
            users[user[:id].to_s] = user
          end

          ForestAdminAgent::Facades::Container.logger.log('Debug', 'Refreshing user permissions cache')

          users
        end[user_id.to_s]
      end

      def get_team(rendering_id)
        permissions = get_rendering_data(rendering_id)

        permissions[:team]
      end

      private

      # An empty list of leaves resolves to no collection at all — a polymorphic relation declaring
      # no `foreign_collections`. `[].all?` would allow it unconditionally, which is the one answer
      # this guard must never give by default, so it counts as denied.
      def readable_leaves?(names, allowed)
        names.any? && names.all? { |name| allowed[name] }
      end

      def leaf_label(names)
        names.empty? ? 'an unresolved polymorphic relation' : "the '#{names.join("' or '")}' collection"
      end

      def fetch_read_permissions(names)
        user_data = get_user_data(caller.id)
        collections_data = get_collections_permissions_data
        results = names.to_h { |name| [name, read_allowed?(collections_data, name, user_data)] }

        return results if results.values.all? || !refetch_denied_reads?(names, collections_data)

        @read_permissions_refetched = true
        refetched = get_collections_permissions_data(force_fetch: true)

        names.to_h { |name| [name, read_allowed?(refetched, name, user_data)] }
      end

      # `can?` refetches the whole environment on every denial. Denial is the steady state of this
      # check rather than the exception, so paying that per denial would cost a permission fetch, and
      # a cache eviction every other in-flight request reads through, on each page load.
      #
      # Two things make a denial worth one fetch. Without `instant_cache_refresh` nothing else keeps
      # the cache fresh — this is the gate node puts its own refetch behind — so a role granted `read`
      # would otherwise stay redacted until the cache expires. With the channel up, `refresh-roles`
      # evicts on a role change, and the only denial staleness still explains is a collection the
      # payload has never heard of.
      def refetch_denied_reads?(names, collections_data)
        return false if @read_permissions_refetched

        !instant_cache_refresh? || names.any? { |name| !collections_data.key?(name.to_sym) }
      end

      def instant_cache_refresh?
        Facades::Container.config_from_cache[:instant_cache_refresh] == true
      end

      def read_allowed?(collections_data, collection_name, user_data)
        return false unless user_data_valid?(user_data)

        collection_key = collection_name.to_sym
        return false unless collection_exists?(collections_data, collection_key, collection_name, user_data)

        role_ids = get_role_ids_for_action(collections_data, collection_key, :read, collection_name, user_data)
        return false unless role_ids

        check_user_permission(role_ids, user_data, :read, collection_name)
      end

      def usage(action, collection, path)
        {
          action: action,
          path: path,
          collections: ForestAdminDatasourceToolkit::Utils::FieldPath.leaf_collection_names(collection, path)
        }
      end

      def collect_search_usages(collection, search, search_extended, usages)
        return if search.nil?

        searched = collection.searched_fields(search, search_extended) if collection.respond_to?(:searched_fields)

        if searched.nil?
          assert_extended_search_checkable(collection, search_extended)

          return
        end

        published = collection.datasource.collections

        searched.each do |field|
          assert_search_target_exposed(field, published)
          usages << { action: 'search on', path: field[:path], collections: field[:collections] }
        end
      end

      # An unknown footprint is a `replace_search` block choosing its own fields. On a plain search
      # the caller aimed at nothing, so it is served — the same category as a scope, and refusing
      # would remove search from every customized collection. The extended flag is the caller's own,
      # though: running one term both ways isolates the rows matched through a relation, a bit per
      # term on collections no check covered. The exemption stops there.
      #
      # A collection that cannot answer at all is read the same way: silence is not an empty
      # footprint either.
      def assert_extended_search_checkable(collection, search_extended)
        return unless search_extended

        raise ForbiddenError,
              "You cannot run an extended search on the '#{collection.name}' collection: the fields " \
              'it reaches cannot be determined, so they cannot be checked against your permissions.'
      end

      # `searched_fields` answers below the publication layer — deliberately, so a field hidden by
      # renaming above it is still checked — so it can name a collection `remove_collection` took out
      # of the API. An extended search does reach through to it: the condition is built below
      # publication, which has already passed the filter down and cannot strip it.
      #
      # That collection is absent from the permission payload too, so asking `read_allowed?` answers
      # "denied" for every role, admins included, and no grant can lift it. So it is refused as what
      # it is — a column the agent does not expose — which points at `disable_search` or publishing
      # the collection again rather than at a permission to grant.
      def assert_search_target_exposed(field, published)
        unexposed = field[:collections].reject { |name| published.key?(name) }

        return if unexposed.empty?

        raise ForbiddenError,
              "You cannot search on '#{field[:path]}': the '#{unexposed.join("' or '")}' collection " \
              'is not exposed by this agent.'
      end

      def permission_allowed?(collections_data, collection, action, user_data)
        return false unless user_data_valid?(user_data)

        collection_key = collection.name.to_sym
        return false unless collection_exists?(collections_data, collection_key, collection.name, user_data)

        role_ids = get_role_ids_for_action(collections_data, collection_key, action, collection.name, user_data)
        return false unless role_ids

        check_user_permission(role_ids, user_data, action, collection.name)
      end

      def get_collections_permissions_data(force_fetch: false)
        self.class.invalidate_cache('forest.collections') if force_fetch == true

        cache.get_or_set('forest.collections') do
          response = fetch('/liana/v4/permissions/environment')
          collections = {}

          response[:collections].each do |name, collection|
            collections[name] = decode_crud_permissions(collection).merge(decode_action_permissions(collection))
          end

          ForestAdminAgent::Facades::Container.logger.log('Debug', 'Fetching environment permissions')

          collections
        end
      end

      def get_chart_data(rendering_id, force_fetch: false)
        rendering_data = get_rendering_data(rendering_id, force_fetch: force_fetch)

        rendering_data[:charts]
      end

      def sanitize_chart_parameters(parameters)
        parameters.delete(:timezone)
        parameters.delete(:collection)
        parameters.delete(:contextVariables)
        parameters.delete(:record_id)
        parameters.delete(:route_alias)
        parameters.delete(:controller)
        parameters.delete(:action)
        parameters.delete(:collection_name)
        parameters.delete(:forest)
        parameters.delete(:format)

        parameters.select { |_, value| !value.nil? && value != '' }
      end

      def array_hash(data)
        Digest::SHA1.hexdigest(data.deep_sort.to_h.to_s)
      end

      def get_rendering_data(rendering_id, force_fetch: false)
        self.class.invalidate_cache('forest.rendering') if force_fetch == true

        cache.get_or_set('forest.rendering') do
          data = {}
          response = fetch("/liana/v4/permissions/renderings/#{rendering_id}")

          data[:scopes] = decode_scope_permissions(response[:collections])
          data[:team] = response[:team]
          data[:segments] = decode_segment_permissions(response[:collections])
          data[:charts] = decode_charts_permissions(response[:stats])
          data[:liveQuerySegments] = decode_live_query_segments_permissions(response[:collections])

          data
        end
      end

      def permission_system?
        cache.get_or_set('forest.has_permission') do
          response = fetch('/liana/v4/permissions/environment')
          { enable: response != true }
        end[:enable]
      end

      def find_action_from_endpoint(collection_name, path, http_method)
        endpoint = path.partition('/forest/')[1..].join
        schema_file = JSON.parse(File.read(Facades::Container.config_from_cache[:schema_path]))
        actions = schema_file['collections']&.find { |collection| collection['name'] == collection_name }&.dig('actions')

        return nil if actions.nil? || actions.empty?

        action = actions.find { |a| a['endpoint'] == endpoint && a['httpMethod'].casecmp(http_method).zero? }

        raise BadRequestError, "The collection #{collection_name} does not have this smart action" if action.nil?

        action
      end

      def decode_crud_permissions(collection)
        unless collection.is_a?(Hash) && collection.key?(:collection)
          ForestAdminAgent::Facades::Container.logger.log(
            'Error',
            'Invalid permissions data structure: missing :collection key. ' \
            "Available keys: #{collection.is_a?(Hash) ? collection.keys.join(", ") : "N/A (not a hash)"}. " \
            'This indicates an API contract violation or data corruption.'
          )
          raise InternalServerError.new(
            'Invalid permission data structure received from Forest Admin API',
            details: { received_keys: collection.is_a?(Hash) ? collection.keys : nil }
          )
        end

        collection_data = collection[:collection]

        unless collection_data.is_a?(Hash)
          ForestAdminAgent::Facades::Container.logger.log(
            'Error',
            "Invalid permissions data: :collection is not a hash (got #{collection_data.class}). " \
            'This indicates an API contract violation or data corruption.'
          )
          raise InternalServerError.new(
            'Invalid permission data structure: :collection must be a hash',
            details: { collection_data_class: collection_data.class }
          )
        end

        {
          browse: collection_data.dig(:browseEnabled, :roles),
          read: collection_data.dig(:readEnabled, :roles),
          edit: collection_data.dig(:editEnabled, :roles),
          add: collection_data.dig(:addEnabled, :roles),
          delete: collection_data.dig(:deleteEnabled, :roles),
          export: collection_data.dig(:exportEnabled, :roles)
        }
      end

      def decode_action_permissions(collection)
        actions = {}
        actions[:actions] = {}
        collection[:actions].each do |id, action|
          actions[:actions][id] = {
            triggerEnabled: action[:triggerEnabled][:roles],
            triggerConditions: action[:triggerConditions],
            approvalRequired: action[:approvalRequired][:roles],
            approvalRequiredConditions: action[:approvalRequiredConditions],
            userApprovalEnabled: action[:userApprovalEnabled][:roles],
            userApprovalConditions: action[:userApprovalConditions],
            selfApprovalEnabled: action[:selfApprovalEnabled][:roles]
          }
        end

        actions
      end

      def decode_scope_permissions(raw_permissions)
        scopes = {}
        raw_permissions.each do |collection_name, value|
          scopes[collection_name] = ConditionTreeFactory.from_plain_object(value[:scope]) unless value[:scope].nil?
        end

        scopes
      end

      def decode_charts_permissions(raw_permissions)
        charts = []

        raw_permissions.each do |chart|
          chart = chart.select { |_, value| !value.nil? && value != '' }
          charts << "#{chart[:type]}:#{array_hash(chart)}"
        end

        charts
      end

      def decode_segment_permissions(raw_permissions)
        segments = {}
        raw_permissions.each do |collection_name, value|
          segments[collection_name] = value[:liveQuerySegments].map { |segment| array_hash(segment) }
        end

        segments
      end

      def decode_live_query_segments_permissions(raw_permissions)
        collections = {}
        raw_permissions.each do |collection_name, value|
          collections[collection_name] = {
            liveQuerySegments: value[:liveQuerySegments] || []
          }
        end

        collections
      end

      def fetch(url)
        response = forest_api.get(url)

        JSON.parse(response.body, symbolize_names: true)
      rescue StandardError => e
        forest_api.handle_response_error(e)
      end

      def user_data_valid?(user_data)
        return true if user_data&.key?(:roleId)

        ForestAdminAgent::Facades::Container.logger.log(
          'Error',
          "Invalid user data: user_data is #{user_data.nil? ? "nil" : "missing :roleId key"}. " \
          'This indicates a session or authentication issue.'
        )
        false
      end

      def collection_exists?(collections_data, collection_key, collection_name, user_data)
        return true if collections_data.key?(collection_key)

        available = collections_data.keys.join(', ')
        ForestAdminAgent::Facades::Container.logger.log(
          'Warn',
          "Collection '#{collection_name}' not found in permissions " \
          "(user_id: #{user_data[:id]}, role_id: #{user_data[:roleId]}). " \
          "Available: #{available.empty? ? "none" : available}. " \
          'This may indicate a configuration mismatch or timing issue during permission refresh.'
        )
        false
      end

      def get_role_ids_for_action(collections_data, collection_key, action, collection_name, user_data)
        collection_permissions = collections_data[collection_key]
        role_ids = collection_permissions[action]

        if role_ids.nil?
          available = collection_permissions.compact.keys.join(', ')
          ForestAdminAgent::Facades::Container.logger.log(
            'Warn',
            "Action '#{action}' not found for collection '#{collection_name}' " \
            "(user_id: #{user_data[:id]}, role_id: #{user_data[:roleId]}). " \
            "Available actions: #{available.empty? ? "none" : available}. " \
            'This may indicate a permission schema change or misconfiguration.'
          )
          return nil
        end

        unless role_ids.is_a?(Array)
          ForestAdminAgent::Facades::Container.logger.log(
            'Error',
            "Invalid permission data: roles for action '#{action}' in collection '#{collection_name}' " \
            "is not an array (got #{role_ids.class}). This indicates data corruption."
          )
          return nil
        end

        role_ids
      end

      def check_user_permission(role_ids, user_data, action, collection_name)
        has_permission = role_ids.include?(user_data[:roleId])

        unless has_permission
          ForestAdminAgent::Facades::Container.logger.log(
            'Debug',
            "Permission denied: User #{user_data[:id]} (role #{user_data[:roleId]}) " \
            "lacks permission to #{action} collection '#{collection_name}'. " \
            "Required roles: #{role_ids.join(", ")}"
          )
        end

        has_permission
      end

      def validate_smart_action_permissions(collections_data, collection, action)
        collection_key = collection.name.to_sym

        unless collections_data.key?(collection_key)
          ForestAdminAgent::Facades::Container.logger.log(
            'Warn',
            "Smart action check: Collection '#{collection.name}' not found in permissions"
          )
          raise ForbiddenError, "Collection '#{collection.name}' not found in permissions"
        end

        collection_actions = collections_data[collection_key][:actions]
        if collection_actions.nil?
          ForestAdminAgent::Facades::Container.logger.log(
            'Warn',
            "Smart action check: No actions configured for collection '#{collection.name}'"
          )
          raise ForbiddenError, "No actions configured for collection '#{collection.name}'"
        end

        action_key = action['name'].to_sym
        unless collection_actions.key?(action_key)
          ForestAdminAgent::Facades::Container.logger.log(
            'Warn',
            "Smart action '#{action["name"]}' not found in permissions for collection '#{collection.name}'"
          )
          raise ForbiddenError, "Smart action '#{action["name"]}' is not configured"
        end

        collection_actions
      end

      def get_collection_rendering_permissions(collection, force_fetch: false)
        rendering_data = get_rendering_data(caller.rendering_id, force_fetch: force_fetch)
        rendering_data[:liveQuerySegments][collection.name.to_sym]
      end

      def segment_permissions_valid?(collection_permissions, query, connection_name)
        IsSegmentQueryAllowedOnConnection.allowed?(collection_permissions, query, connection_name)
      end
    end
  end
end
