module ForestAdminAgent
  module Services
    class SmartActionChecker
      include ForestAdminAgent::Http::Exceptions
      include ForestAdminAgent::Utils
      include ForestAdminDatasourceToolkit::Utils
      include ForestAdminDatasourceToolkit::Components::Query

      TRIGGER_FORBIDDEN_ERROR = 'CustomActionTriggerForbiddenError'.freeze

      INVALID_ACTION_CONDITION_ERROR = 'InvalidActionConditionError'.freeze

      def initialize(parameters, collection, smart_action, user)
        @parameters = parameters
        @attributes = @parameters[:data][:attributes]
        @collection = collection
        @smart_action = smart_action
        @user = user
      end

      def can_execute?
        if @attributes[:signed_approval_request].present? &&
           @smart_action['userApprovalEnabled'].include?(@user['roleId'])
          can_approve?
        else
          can_trigger?
        end
      end

      private

      def can_approve?
        @parameters = RequestPermission.decodeSignedApprovalRequest(@parameters)
        if (@smart_action['userApprovalConditions'].empty? || match_conditions('userApprovalConditions')) &&
           (@attributes[:requester_id] != @user['id'] || @smart_action['selfApprovalEnabled'].include?(@user['roleId']))

          return true
        end

        raise ForbiddenError.new('You don\'t have the permission to trigger this action.', TRIGGER_FORBIDDEN_ERROR)
      end

      def can_trigger?
        if @smart_action['triggerEnabled'].include?(@user['roleId']) &&
           @smart_action['approvalRequired'].exclude?(@user['roleId'])
          return true if @smart_action['triggerConditions'].empty? || match_conditions('triggerConditions')
        elsif @smart_action['approvalRequired'].include?(@user['roleId'])
          if @smart_action['approvalRequiredConditions'].empty? || match_conditions('approvalRequiredConditions')
            raise RequireApproval, @smart_action['userApprovalEnabled']
          end
          return true if @smart_action['triggerConditions'].empty? || match_conditions('triggerConditions')
        end

        raise ForbiddenError.new('You don\'t have the permission to trigger this action.', TRIGGER_FORBIDDEN_ERROR)
      end

      def match_conditions(condition_name)
        pk = Schema.primary_keys(@collection)[0]
        condition_filter = if attributes[:all_records]
                             Nodes::ConditionTreeLeaf.new(pk, 'NOT_EQUAL', @attributes[:all_records_ids_excluded])
                           else
                             Nodes::ConditionTreeLeaf.new(pk, 'IN', @attributes[:ids])
                           end

        condition = @smart_action[condition_name][0]['filter']
        conditional_filter = @filter.override(
          condition_tree: ConditionTree::ConditionTreeFactory.intersect(
            [
              ConditionTreeParser.from_plain_object(@collection, condition),
              @filter.get_condition_tree,
              condition_filter
            ]
          )
        )
        rows = @collection.aggregate(@caller, conditional_filter, Aggregation.new(operation: 'Count'))

        (rows[0]['value'] || 0) == attributes[:ids].count
      rescue StandardError
        raise ConflictError.new(
          'The conditions to trigger this action cannot be verified. Please contact an administrator.',
          INVALID_ACTION_CONDITION_ERROR
        )
      end
    end
  end
end
