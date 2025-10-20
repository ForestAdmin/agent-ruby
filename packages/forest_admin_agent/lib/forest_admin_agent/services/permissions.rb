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

        # First check
        is_allowed = permission_allowed?(collections_data, collection, action, user_data)

        # Refetch if not allowed
        unless is_allowed
          collections_data = get_collections_permissions_data(force_fetch: true)
          is_allowed = permission_allowed?(collections_data, collection, action, user_data)
        end

        # still not allowed - throw forbidden message
        raise ForbiddenError, "You don't have permission to #{action} this collection." unless is_allowed

        is_allowed
      end

      def can_chart?(parameters)
        attributes = sanitize_chart_parameters(parameters.deep_symbolize_keys)
        hash_request = "#{attributes[:type]}:#{array_hash(attributes)}"
        is_allowed = get_chart_data(caller.rendering_id).include?(hash_request)

        # Refetch
        is_allowed ||= get_chart_data(caller.rendering_id, force_fetch: true).include?(hash_request)

        # still not allowed - throw forbidden message
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
        hash_request = array_hash({ query: query, connectionName: connection_name })
        is_allowed = get_segments(collection).include?(hash_request)

        # Refetch
        is_allowed ||= get_segments(collection, force_fetch: true).include?(hash_request)

        # still not allowed - throw forbidden message
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

        collection_key = collection.name.to_sym

        # Validate collection exists in permissions
        unless collections_data.key?(collection_key)
          ForestAdminAgent::Facades::Container.logger.log(
            'Warn',
            "Smart action check: Collection '#{collection.name}' not found in permissions"
          )
          raise ForbiddenError, "Collection '#{collection.name}' not found in permissions"
        end

        # Validate actions exist for collection
        collection_actions = collections_data[collection_key][:actions]
        if collection_actions.nil?
          ForestAdminAgent::Facades::Container.logger.log(
            'Warn',
            "Smart action check: No actions configured for collection '#{collection.name}'"
          )
          raise ForbiddenError, "No actions configured for collection '#{collection.name}'"
        end

        # Validate specific action exists
        action_key = action['name'].to_sym
        unless collection_actions.key?(action_key)
          ForestAdminAgent::Facades::Container.logger.log(
            'Warn',
            "Smart action '#{action["name"]}' not found in permissions for collection '#{collection.name}'"
          )
          raise ForbiddenError, "Smart action '#{action["name"]}' is not configured"
        end

        smart_action_approval = SmartActionChecker.new(
          request[:params],
          collection,
          collection_actions[action_key],
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

      def permission_allowed?(collections_data, collection, action, user_data)
        # Validate user_data exists and has roleId
        if user_data.nil? || !user_data.key?(:roleId)
          ForestAdminAgent::Facades::Container.logger.log(
            'Error',
            "Invalid user data: user_data is #{user_data.nil? ? "nil" : "missing :roleId key"}. " \
            'This indicates a session or authentication issue.'
          )
          return false
        end

        collection_key = collection.name.to_sym

        # Validate collection exists in permissions data
        # (collection may have been removed from permissions during refetch)
        unless collections_data.key?(collection_key)
          available = collections_data.keys.join(', ')
          ForestAdminAgent::Facades::Container.logger.log(
            'Warn',
            "Collection '#{collection.name}' not found in permissions " \
            "(user_id: #{user_data[:id]}, role_id: #{user_data[:roleId]}). " \
            "Available: #{available.empty? ? "none" : available}. " \
            'This may indicate a configuration mismatch or timing issue during permission refresh.'
          )
          return false
        end

        # Validate action exists in collection permissions
        # (action may have been removed from collection during refetch)
        collection_permissions = collections_data[collection_key]
        role_ids = collection_permissions[action]

        if role_ids.nil?
          available = collection_permissions.compact.keys.join(', ')
          ForestAdminAgent::Facades::Container.logger.log(
            'Warn',
            "Action '#{action}' not found for collection '#{collection.name}' " \
            "(user_id: #{user_data[:id]}, role_id: #{user_data[:roleId]}). " \
            "Available actions: #{available.empty? ? "none" : available}. " \
            'This may indicate a permission schema change or misconfiguration.'
          )
          return false
        end

        # Handle case where roles array itself is nil (not just missing action)
        unless role_ids.is_a?(Array)
          ForestAdminAgent::Facades::Container.logger.log(
            'Error',
            "Invalid permission data: roles for action '#{action}' in collection '#{collection.name}' " \
            "is not an array (got #{role_ids.class}). This indicates data corruption."
          )
          return false
        end

        # Check if user's role is authorized for this action
        has_permission = role_ids.include?(user_data[:roleId])

        unless has_permission
          # This is normal - log at Debug since it's expected behavior
          ForestAdminAgent::Facades::Container.logger.log(
            'Debug',
            "Permission denied: User #{user_data[:id]} (role #{user_data[:roleId]}) " \
            "lacks permission to #{action} collection '#{collection.name}'. " \
            "Required roles: #{role_ids.join(", ")}"
          )
        end

        has_permission
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
        # rails
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
        actions = schema_file['collections']&.select { |collection| collection['name'] == collection_name }&.first&.dig('actions')

        return nil if actions.nil? || actions.empty?

        action = actions.find { |a| a['endpoint'] == endpoint && a['httpMethod'].casecmp(http_method).zero? }

        raise ForestException, "The collection #{collection_name} does not have this smart action" if action.nil?

        action
      end

      def decode_crud_permissions(collection)
        # Validate structure exists
        unless collection.is_a?(Hash) && collection.key?(:collection)
          ForestAdminAgent::Facades::Container.logger.log(
            'Error',
            'Invalid permissions data structure: missing :collection key. ' \
            "Available keys: #{collection.is_a?(Hash) ? collection.keys.join(", ") : "N/A (not a hash)"}. " \
            'This indicates an API contract violation or data corruption.'
          )
          raise ForestException, 'Invalid permission data structure received from Forest Admin API'
        end

        collection_data = collection[:collection]

        unless collection_data.is_a?(Hash)
          ForestAdminAgent::Facades::Container.logger.log(
            'Error',
            "Invalid permissions data: :collection is not a hash (got #{collection_data.class}). " \
            'This indicates an API contract violation or data corruption.'
          )
          raise ForestException, 'Invalid permission data structure: :collection must be a hash'
        end

        # Use dig to safely extract roles, allowing for missing permissions
        # Missing permissions will result in nil values which are handled by permission_allowed?
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

      def fetch(url)
        response = forest_api.get(url)

        JSON.parse(response.body, symbolize_names: true)
      rescue StandardError => e
        forest_api.handle_response_error(e)
      end
    end
  end
end
