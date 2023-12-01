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
        @cache = Lightly.new(
          life: Facades::Container.config_from_cache[:permission_expiration],
          dir: "#{Facades::Container.config_from_cache[:cache_dir]}/permissions"
        )
      end

      def self.invalidate_cache(id_cache)
        cache = Lightly.new(
          life: Facades::Container.config_from_cache[:permission_expiration],
          dir: "#{Facades::Container.config_from_cache[:cache_dir]}/permissions"
        )
        cache.clear id_cache
        # ...
        # TODO: HANDLE LOGGER
        # logger.debug("Invalidating #{id_cache} cache..")
      end

      def can?(action, collection, allow_fetch: false)
        return true unless permission_system?

        user_data = get_user_data(caller.id)
        collections_data = get_collections_permissions_data(force_fetch: allow_fetch)

        is_allowed = collections_data.key?(collection.name.to_sym) && collections_data[collection.name.to_sym][action].include?(user_data[:roleId])

        # Refetch
        unless is_allowed
          collections_data = get_collections_permissions_data(force_fetch: true)
          is_allowed = collections_data[collection.name.to_sym][action].include?(user_data[:roleId])
        end

        # still not allowed - throw forbidden message
        raise ForbiddenError, "You don't have permission to #{action} this collection." unless is_allowed

        is_allowed
      end

      def can_chart?(parameters)
        attributes = sanitize_chart_parameters(parameters)
        hash_request = "#{attributes[:type]}:#{array_hash(attributes)}"
        is_allowed = get_chart_data(caller.rendering_id).include?(hash_request)

        # Refetch
        is_allowed ||= get_chart_data(caller.rendering_id, force_fetch: true).include?(hash_request)

        # still not allowed - throw forbidden message
        unless is_allowed
          # TODO: HANDLE LOGGER
          # logger.debug("User #{caller.id} cannot retrieve chart on rendering #{caller.rendering_id}")
          raise ForbiddenError, "You don't have permission to access this collection."
        end

        # TODO: HANDLE LOGGER
        # logger.debug("User #{caller.id} can retrieve chart on rendering #{caller.rendering_id}")

        is_allowed
      end

      def can_smart_action?(request, collection, filter, allow_fetch: true)
        return true unless permission_system?

        user_data = get_user_data(caller.id)
        collections_data = get_collections_permissions_data(force_fetch: allow_fetch)
        action = find_action_from_endpoint(collection.name.to_sym, request.path_info, request.method)

        raise ForestException, "The collection #{collection.name.to_sym} does not have this smart action" if action.nil?

        smart_action_approval = SmartActionChecker.new(
          request,
          collection,
          collections_data[collection.name.to_sym][:actions][action[:name]],
          caller,
          user_data[:roleId],
          filter
        )

        smart_action_approval.can_execute?
        # TODO: HANDLE LOGGER
        # logger.debug("User #{user_data[:roleId]} is #{is_allowed ? '' : 'not'} allowed to perform #{action['name']}")
      end

      def get_scope(collection)
        permissions = get_scope_and_team_data(caller.rendering_id)
        scope = permissions[:scopes][collection.name.to_sym]
        team = permissions[:team]
        user = get_user_data(caller.id)

        return nil if scope.nil?

        context_variables = ContextVariables.new(team, user)

        ContextVariablesInjector.inject_context_in_filter(scope, context_variables)
      end

      def get_user_data(user_id)
        cache.get('forest.users') do
          response = fetch('/liana/v4/permissions/users')
          users = {}

          response.each do |user|
            users[user[:id].to_s] = user
          end

          # TODO: HANDLE LOGGER
          # logger.debug('Refreshing user permissions cache')

          users
        end[user_id.to_s]
      end

      def get_team(rendering_id)
        permissions = get_scope_and_team_data(rendering_id)

        permissions[:team]
      end

      private

      def get_collections_permissions_data(force_fetch: false)
        self.class.invalidate_cache('forest.collections') if force_fetch == true

        cache.get('forest.collections') do
          response = fetch('/liana/v4/permissions/environment')
          collections = {}

          response[:collections].each do |name, collection|
            collections[name] = decode_crud_permissions(collection).merge(decode_action_permissions(collection))
          end

          # TODO: HANDLE LOGGER
          # logger.debug('Fetching environment permissions')

          collections
        end
      end

      def get_chart_data(rendering_id, force_fetch: false)
        self.class.invalidate_cache('forest.stats') if force_fetch == true

        cache.get('forest.stats') do
          response = fetch("/liana/v4/permissions/renderings/#{rendering_id}")
          stat_hash = []
          response[:stats].each do |stat|
            stat = stat.select { |_, value| !value.nil? && value != '' }
            stat_hash << "#{stat[:type]}:#{array_hash(stat)}"
          end

          # TODO: HANDLE LOGGER
          # logger.debug("Loading rendering permissions for rendering #{rendering_id}")

          stat_hash
        end
      end

      def sanitize_chart_parameters(parameters)
        # parameters = parameters.to_h
        parameters.delete(:timezone)
        parameters.delete(:collection)
        parameters.delete(:contextVariables)

        parameters.select { |_, value| !value.nil? && value != '' }
      end

      # protected function arrayHash(array $data): string
      # {
      #   ArrayHelper::ksortRecursive($data);
      #
      # return sha1(json_encode($data, JSON_THROW_ON_ERROR));
      # stat_hash << "#{stat['type']}:#{Digest::SHA1.hexdigest(stat.sort.to_h.to_s)}"
      # }
      def array_hash(data)
        # data.deep_sort.to_s

        Digest::SHA1.hexdigest(data.sort.to_h.to_s)
      end

      def get_scope_and_team_data(rendering_id)
        cache.get('forest.scopes') do
          data = {}
          response = fetch("/liana/v4/permissions/renderings/#{rendering_id}")

          data[:scopes] = decode_scope_permissions(response[:collections])
          data[:team] = response[:team]

          data
        end
      end

      def permission_system?
        cache.get('forest.has_permission') do
          response = fetch('/liana/v4/permissions/environment')
          !response.nil?
        end
      end

      def find_action_from_endpoint(collection_name, endpoint, http_method)
        actions = ForestSchema.get_smart_actions(collection_name)

        return nil if actions.empty?

        actions.find { |action| action['endpoint'] == endpoint && action['httpMethod'] == http_method }
      end

      def decode_crud_permissions(collection)
        {
          browse: collection[:collection][:browseEnabled][:roles],
          read: collection[:collection][:readEnabled][:roles],
          edit: collection[:collection][:editEnabled][:roles],
          add: collection[:collection][:addEnabled][:roles],
          delete: collection[:collection][:deleteEnabled][:roles],
          export: collection[:collection][:exportEnabled][:roles]
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

      def fetch(url)
        response = forest_api.get(url)

        JSON.parse(response.body, symbolize_names: true)
      rescue StandardError => e
        forest_api.handle_response_error(e)
      end
    end
  end
end
