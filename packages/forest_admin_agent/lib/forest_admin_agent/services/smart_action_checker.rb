module ForestAdminAgent
  module Services
    include ForestAdminAgent::Http::Exceptions

    class CustomActionTriggerForbiddenError < ForbiddenError
      def initialize(message = 'Custom action trigger forbidden', details: {})
        super
      end
    end

    class InvalidActionConditionError < ConflictError
      def initialize(message = 'Invalid action condition', details: {})
        super
      end
    end

    class CustomActionRequiresApprovalError < ForbiddenError
      def initialize(message = 'Custom action requires approval', details: {})
        super
      end
    end

    class SmartActionChecker
      include ForestAdminAgent::Utils
      include ForestAdminDatasourceToolkit::Utils
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

      attr_reader :parameters, :collection, :smart_action, :caller, :role_id, :filter, :attributes

      def initialize(parameters, collection, smart_action, caller, role_id, filter)
        @parameters = parameters
        @collection = collection
        @smart_action = smart_action
        @caller = caller
        @role_id = role_id
        @filter = filter
        @attributes = parameters[:data][:attributes]
      end

      def can_execute?
        if attributes[:signed_approval_request].nil?
          can_trigger?
        else
          can_approve?
        end
      end

      private

      def can_approve?
        if smart_action[:userApprovalEnabled].include?(role_id) &&
           (condition_by_role_id(smart_action[:userApprovalConditions]).nil? || match_conditions(:userApprovalConditions)) &&
           (attributes[:signed_approval_request][:data][:attributes][:requester_id] != caller.id ||
             smart_action[:selfApprovalEnabled].include?(role_id))
          return true
        end

        raise CustomActionTriggerForbiddenError, 'You don\'t have the permission to trigger this action.'
      end

      def can_trigger?
        if smart_action[:triggerEnabled].include?(role_id) && !smart_action[:approvalRequired].include?(role_id)
          if condition_by_role_id(smart_action[:triggerConditions]).nil? || match_conditions(:triggerConditions)
            return true
          end
        elsif smart_action[:approvalRequired].include?(role_id) && smart_action[:triggerEnabled].include?(role_id)
          if condition_by_role_id(smart_action[:approvalRequiredConditions]).nil? || match_conditions(:approvalRequiredConditions)
            raise CustomActionRequiresApprovalError.new(
              'This action requires to be approved.',
              details: { user_approval_enabled: smart_action[:userApprovalEnabled] }
            )
          elsif condition_by_role_id(smart_action[:triggerConditions]).nil? || match_conditions(:triggerConditions)
            return true
          end
        end

        raise CustomActionTriggerForbiddenError, 'You don\'t have the permission to trigger this action.'
      end

      def match_conditions(condition_name)
        pks = Schema.primary_keys(collection)

        if pks.nil? || pks.empty?
          ForestAdminAgent::Facades::Container.logger.log(
            'Error',
            "Missing primary keys for action with conditional permissions - Collection: #{collection.name}, " \
            "Action: #{attributes[:smart_action_id]}"
          )

          raise UnprocessableError, "Collection '#{collection.name}' has no primary keys. " \
                                    'Actions with conditional permissions require a primary key to identify records.'
        end

        pk = pks[0]
        condition_filter = if attributes[:all_records]
                             Nodes::ConditionTreeLeaf.new(pk, 'NOT_EQUAL', attributes[:all_records_ids_excluded])
                           else
                             Nodes::ConditionTreeLeaf.new(pk, 'IN', attributes[:ids])
                           end
        condition = condition_by_role_id(smart_action[condition_name])
        conditional_filter = filter.override(
          condition_tree: ConditionTreeFactory.intersect(
            [
              ConditionTreeParser.from_plain_object(collection, condition[:filter]),
              filter.condition_tree,
              condition_filter
            ]
          )
        )

        rows = collection.aggregate(caller, conditional_filter, Aggregation.new(operation: 'Count'))
        (rows.empty? ? 0 : rows[0]['value']) == attributes[:ids].count
      rescue ForestAdminDatasourceToolkit::Exceptions::ForestException, BusinessError => e
        # Let primary key validation errors propagate - these are actionable schema issues
        # Wrap other exceptions (like invalid operators) in ConflictError
        raise if e.message.include?('has no primary keys')

        raise InvalidActionConditionError, 'The conditions to trigger this action cannot be verified. Please contact an administrator.'
      rescue ArgumentError, TypeError => e
        # Catch specific errors from condition parsing/validation
        raise InvalidActionConditionError, "Invalid action condition: #{e.message}. Please contact an administrator."
      rescue StandardError => e
        # Catch unexpected errors and log for debugging
        ForestAdminAgent::Facades::Container.logger.log(
          'Error',
          "Unexpected error in match_conditions: #{e.class} - #{e.message}"
        )

        raise InvalidActionConditionError, 'The conditions to trigger this action cannot be verified. Please contact an administrator.'
      end

      def condition_by_role_id(condition)
        condition.find { |c| c['roleId'] == role_id }
      end
    end
  end
end
