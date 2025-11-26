# frozen_string_literal: true

# Ensure dependencies are fully loaded before referencing their constants
require 'forest_admin_datasource_toolkit'
require 'forest_admin_datasource_customizer'
require 'forest_admin_agent'

# ForestAdmin::Types provides a convenient way to access commonly-used classes
# from ForestAdmin packages without requiring multiple includes.
#
# Usage:
#   include ForestAdmin::Types
#
#   # Now you can use short class names:
#   ConditionTreeLeaf.new('status', Operators::EQUAL, 'active')
#   Filter.new(condition_tree: tree)
#   Aggregation.new(operation: 'Count', field: 'id')
#
#   # In action blocks, result_builder is an ActionResultBuilder:
#   result_builder.success(message: 'Done!')
#   result_builder.file(content: data, name: 'export.csv')
#
#   # In chart blocks, result_builder is a ChartResultBuilder:
#   result_builder.value(42)
#   result_builder.distribution({ 'Active' => 10, 'Inactive' => 5 })
#
#   # Factory classes for building complex objects:
#   tree = ConditionTreeFactory.from_plain_object({ field: 'status', operator: 'equal', value: 'active' })
#   filter = ConditionTreeFactory.match_ids(collection, [1, 2, 3])
#   combined = ConditionTreeFactory.intersect([tree1, tree2])
#   projection = ProjectionFactory.all(collection)
#   sort = SortFactory.by_primary_keys(collection)
#
#   # Exception handling in hooks and actions:
#   raise ValidationError.new('Invalid input') if invalid?
#   raise ForbiddenError.new('Access denied') unless authorized?
#   raise UnprocessableError.new('Cannot process request')
#
#   # Context classes for different handlers:
#   # - ChartContext: context.get_record(['field1', 'field2'])
#   # - HookContext: context.raise_validation_error('Error message')
#
module ForestAdmin
  module Types
    # ============================================
    # Query Components
    # ============================================

    # Filter - used to filter records in queries
    Filter = ForestAdminDatasourceToolkit::Components::Query::Filter

    # Aggregation - used for aggregate operations (Count, Sum, Avg, etc.)
    Aggregation = ForestAdminDatasourceToolkit::Components::Query::Aggregation

    # Projection - specifies which fields to retrieve
    Projection = ForestAdminDatasourceToolkit::Components::Query::Projection

    # Page - pagination parameters
    Page = ForestAdminDatasourceToolkit::Components::Query::Page

    # Sort - sorting parameters
    Sort = ForestAdminDatasourceToolkit::Components::Query::Sort

    # ============================================
    # Condition Tree
    # ============================================

    # ConditionTreeLeaf - a single condition (field, operator, value)
    ConditionTreeLeaf = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

    # ConditionTreeBranch - combines multiple conditions with And/Or
    ConditionTreeBranch = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeBranch

    # Operators - all available operators (EQUAL, GREATER_THAN, CONTAINS, etc.)
    Operators = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators

    # ============================================
    # Action Types
    # ============================================

    # FieldType - field types for action forms (STRING, NUMBER, BOOLEAN, etc.)
    FieldType = ForestAdminDatasourceCustomizer::Decorators::Action::Types::FieldType

    # ActionScope - action scopes (SINGLE, BULK, GLOBAL)
    ActionScope = ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope

    # BaseAction - base class for defining actions
    BaseAction = ForestAdminDatasourceCustomizer::Decorators::Action::BaseAction

    # ============================================
    # Action Contexts
    # ============================================

    # ActionContext - execution context for Bulk/Global actions
    ActionContext = ForestAdminDatasourceCustomizer::Decorators::Action::Context::ActionContext

    # ActionContextSingle - execution context for Single actions
    ActionContextSingle = ForestAdminDatasourceCustomizer::Decorators::Action::Context::ActionContextSingle

    # ActionResultBuilder - builder for action results (success, error, file, webhook)
    ActionResultBuilder = ForestAdminDatasourceCustomizer::Decorators::Action::ResultBuilder

    # ============================================
    # Charts
    # ============================================

    # ChartResultBuilder - builder for chart results (value, distribution, time_based, etc.)
    ChartResultBuilder = ForestAdminDatasourceCustomizer::Decorators::Chart::ResultBuilder

    # ============================================
    # Computed Fields
    # ============================================

    # ComputedDefinition - defines computed/virtual fields
    ComputedDefinition = ForestAdminDatasourceCustomizer::Decorators::Computed::ComputedDefinition

    # ============================================
    # User/Caller Information
    # ============================================

    # Caller - represents the user making the request (email, timezone, team, etc.)
    Caller = ForestAdminDatasourceToolkit::Components::Caller

    # ============================================
    # Plugins
    # ============================================

    # Plugin - base class for creating custom plugins
    Plugin = ForestAdminDatasourceCustomizer::Plugins::Plugin

    # ============================================
    # Additional Context Classes
    # ============================================

    # ChartContext - execution context for chart handlers
    # Methods: get_record(fields), record_id, composite_record_id
    ChartContext = ForestAdminDatasourceCustomizer::Decorators::Chart::ChartContext

    # HookContext - execution context for hook handlers
    # Methods: raise_validation_error, raise_forbidden_error, raise_error
    HookContext = ForestAdminDatasourceCustomizer::Decorators::Hook::Context::HookContext

    # ============================================
    # Exception Classes
    # ============================================

    # BusinessError - base class for all business errors
    BusinessError = ForestAdminAgent::Http::Exceptions::BusinessError

    # Specific error types for better error handling
    ValidationError = ForestAdminAgent::Http::Exceptions::ValidationError
    ForbiddenError = ForestAdminAgent::Http::Exceptions::ForbiddenError
    UnauthorizedError = ForestAdminAgent::Http::Exceptions::UnauthorizedError
    NotFoundError = ForestAdminAgent::Http::Exceptions::NotFoundError
    UnprocessableError = ForestAdminAgent::Http::Exceptions::UnprocessableError
    BadRequestError = ForestAdminAgent::Http::Exceptions::BadRequestError

    # ============================================
    # Factory Classes
    # ============================================

    # ConditionTreeFactory - factory methods for creating condition trees
    # Methods: from_plain_object, match_ids, match_records, intersect, union, match_none
    ConditionTreeFactory = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::ConditionTreeFactory

    # FilterFactory - factory methods for creating filters
    # Methods: from_plain_object, make_foreign_filter, make_through_filter
    FilterFactory = ForestAdminDatasourceToolkit::Components::Query::FilterFactory

    # ProjectionFactory - factory methods for creating projections
    # Methods: all(collection)
    ProjectionFactory = ForestAdminDatasourceToolkit::Components::Query::ProjectionFactory

    # SortFactory - factory methods for creating sort clauses
    # Methods: by_primary_keys(collection)
    SortFactory = ForestAdminDatasourceToolkit::Components::Query::SortUtils::SortFactory

    # ============================================
    # Module inclusion support
    # ============================================

    def self.included(base)
      # When included, define constants on the including class/module
      # This allows using `include ForestAdmin::Types` and then referencing
      # the types directly without the ForestAdmin::Types prefix
      constants.each do |const_name|
        base.const_set(const_name, const_get(const_name)) unless base.const_defined?(const_name)
      end
    end
  end
end
