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

      # Whether the caller may read each of +collection_names+.
      #
      # +root_collection_name+ is pinned to readable and never looked up: +browse+ already gates a
      # listing, +read+ a get, and the signed hash a chart.
      #
      # One cached pass for the whole request, and a single refetch only if it denied something —
      # unlike +can?+, which refetches on every denial. Denial is the steady state here rather than
      # the exception, so refetching per collection would cost one permission fetch per request.
      def read_permissions(root_collection_name, collection_names)
        to_check = collection_names.uniq.reject { |name| name == root_collection_name }
        allowed = { root_collection_name => true }

        return allowed if to_check.empty? || !permission_system?

        user_data = get_user_data(caller.id)
        collections_data = get_collections_permissions_data
        results = to_check.to_h { |name| [name, read_allowed?(collections_data, name, user_data)] }

        unless results.values.all?
          collections_data = get_collections_permissions_data(force_fetch: true)
          results = to_check.to_h { |name| [name, read_allowed?(collections_data, name, user_data)] }
        end

        allowed.merge(results)
      end

      # An unnamed field is dropped rather than refused: the default expansion covers every column
      # of every to-one relation, so refusing would turn an ordinary listing into a 403 for a caller
      # that asked for nothing.
      def redact_projection(collection, projection, named_by_caller:)
        owners = projection.to_h do |path|
          [path, ForestAdminDatasourceToolkit::Utils::FieldPath.leaf_collection_names(collection, path)]
        end
        allowed = read_permissions(collection.name, owners.values.flatten)
        readable = ->(path) { owners[path].all? { |name| allowed[name] } }

        if named_by_caller
          denied = projection.reject { |path| readable.call(path) }

          unless denied.empty?
            fields = denied.map { |path| "'#{path}' from the '#{owners[path].join("' or '")}' collection" }
            raise ForbiddenError, "You are not allowed to read #{fields.join(", ")}."
          end
        end

        ForestAdminDatasourceToolkit::Components::Query::Projection.new(projection.select { |path| readable.call(path) })
      end

      # Refused rather than redacted: dropping a condition widens the result set and dropping a sort
      # clause silently reorders it, while both leak the value they touch anyway — a `starts_with`
      # filter answers one guess per request without returning a column of its own.
      def assert_can_read_query_fields(collection, args)
        usages = []
        push = lambda do |action, path|
          usages << {
            action: action,
            path: path,
            collections: ForestAdminDatasourceToolkit::Utils::FieldPath.leaf_collection_names(collection, path)
          }
        end

        # `for_each_leaf` on a branch replaces each condition with the block's return value, so the
        # leaf has to come back out or the tree is rebuilt from whatever `push` returned.
        Utils::QueryStringParser.parse_condition_tree(collection, args)&.for_each_leaf do |leaf|
          push.call('filter on', leaf.field)
          leaf
        end

        Utils::QueryStringParser.parse_sort(collection, args).each { |clause| push.call('sort on', clause[:field]) }

        assert_can_read_search(collection, args, usages)
        assert_can_read_usages(collection.name, usages)
      end

      def assert_can_read_usages(root_collection_name, usages)
        allowed = read_permissions(root_collection_name, usages.flat_map { |usage| usage[:collections] })
        denied = usages.find { |usage| !usage[:collections].all? { |name| allowed[name] } }

        return unless denied

        raise ForbiddenError,
              "You cannot #{denied[:action]} '#{denied[:path]}': you are not allowed to read the " \
              "'#{denied[:collections].join("' or '")}' collection."
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
          collection_actions[action['name'].to_sym],
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

      def read_allowed?(collections_data, collection_name, user_data)
        return false unless user_data_valid?(user_data)

        collection_key = collection_name.to_sym
        return false unless collection_exists?(collections_data, collection_key, collection_name, user_data)

        role_ids = get_role_ids_for_action(collections_data, collection_key, :read, collection_name, user_data)
        return false unless role_ids

        check_user_permission(role_ids, user_data, :read, collection_name)
      end

      # Asked of the stack, not derived from the schema: the fields an extended search reaches are
      # read below the publication and renaming layers, and only that layer knows whether a replacer
      # or a natively searchable datasource has taken the choice out of its hands.
      def assert_can_read_search(collection, args, usages)
        search = Utils::QueryStringParser.parse_search(collection, args)

        return if search.nil? || !collection.respond_to?(:searched_fields)

        extended = Utils::QueryStringParser.parse_search_extended(args)
        searched = collection.searched_fields(search, extended)

        searched&.each do |field|
          usages << { action: 'search on', path: field[:path], collections: field[:collections] }
        end
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
