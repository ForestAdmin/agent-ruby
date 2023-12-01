module ForestAdminAgent
  module Services
    class SmartActionChecker
      include ForestAdminAgent::Http::Exceptions
      include ForestAdminAgent::Utils
      include ForestAdminDatasourceToolkit::Utils
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

      attr_reader :parameters, :collection, :smart_action, :caller, :role_id, :filter, :attributes

      TRIGGER_FORBIDDEN_ERROR = 'CustomActionTriggerForbiddenError'.freeze

      REQUIRE_APPROVAL_ERROR = 'CustomActionRequiresApprovalError'.freeze

      INVALID_ACTION_CONDITION_ERROR = 'InvalidActionConditionError'.freeze

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
           (smart_action[:userApprovalConditions].empty? || match_conditions(:userApprovalConditions)) &&
           (attributes[:requester_id] != caller.id || smart_action[:selfApprovalEnabled].include?(role_id))
          return true
        end

        raise ForbiddenError.new('You don\'t have the permission to trigger this action.', TRIGGER_FORBIDDEN_ERROR)
      end

      def can_trigger?
        if smart_action[:triggerEnabled].include?(role_id) && !smart_action[:approvalRequired].include?(role_id)
          return true if smart_action[:triggerConditions].empty? || match_conditions(:triggerConditions)
        elsif smart_action[:approvalRequired].include?(role_id) && smart_action[:triggerEnabled].include?(role_id)
          if smart_action[:approvalRequiredConditions].empty? || match_conditions(:approvalRequiredConditions)
            raise RequireApproval.new(
              'This action requires to be approved.',
              REQUIRE_APPROVAL_ERROR,
              smart_action[:userApprovalEnabled]
            )
          elsif smart_action[:triggerConditions].empty? || match_conditions(:triggerConditions)
            return true
          end
        end

        raise ForbiddenError.new('You don\'t have the permission to trigger this action.', TRIGGER_FORBIDDEN_ERROR)
      end

      def match_conditions(condition_name)
        pk = Schema.primary_keys(collection)[0]
        condition_filter = if attributes[:all_records]
                             Nodes::ConditionTreeLeaf.new(pk, 'NOT_EQUAL', attributes[:all_records_ids_excluded])
                           else
                             Nodes::ConditionTreeLeaf.new(pk, 'IN', attributes[:ids])
                           end

        condition = smart_action[condition_name][0]['filter']
        conditional_filter = filter.override(
          condition_tree: ConditionTreeFactory.intersect(
            [
              ConditionTreeParser.from_plain_object(collection, condition),
              filter.condition_tree,
              condition_filter
            ]
          )
        )
        rows = collection.aggregate(caller, conditional_filter, Aggregation.new(operation: 'Count'))

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
