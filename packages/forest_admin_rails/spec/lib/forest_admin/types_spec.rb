# frozen_string_literal: true

require 'spec_helper'

# Load dependencies required by ForestAdmin::Types
require 'forest_admin_datasource_toolkit'
require 'forest_admin_datasource_customizer'
require_relative '../../../lib/forest_admin/types'

RSpec.describe ForestAdmin::Types do
  describe 'module constants' do
    it 'exports Filter' do
      expect(described_class::Filter).to eq(ForestAdminDatasourceToolkit::Components::Query::Filter)
    end

    it 'exports Aggregation' do
      expect(described_class::Aggregation).to eq(ForestAdminDatasourceToolkit::Components::Query::Aggregation)
    end

    it 'exports Projection' do
      expect(described_class::Projection).to eq(ForestAdminDatasourceToolkit::Components::Query::Projection)
    end

    it 'exports Page' do
      expect(described_class::Page).to eq(ForestAdminDatasourceToolkit::Components::Query::Page)
    end

    it 'exports Sort' do
      expect(described_class::Sort).to eq(ForestAdminDatasourceToolkit::Components::Query::Sort)
    end

    it 'exports ConditionTreeLeaf' do
      expect(described_class::ConditionTreeLeaf).to eq(
        ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf
      )
    end

    it 'exports ConditionTreeBranch' do
      expect(described_class::ConditionTreeBranch).to eq(
        ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeBranch
      )
    end

    it 'exports Operators' do
      expect(described_class::Operators).to eq(
        ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators
      )
    end

    it 'exports FieldType' do
      expect(described_class::FieldType).to eq(
        ForestAdminDatasourceCustomizer::Decorators::Action::Types::FieldType
      )
    end

    it 'exports ActionScope' do
      expect(described_class::ActionScope).to eq(
        ForestAdminDatasourceCustomizer::Decorators::Action::Types::ActionScope
      )
    end

    it 'exports BaseAction' do
      expect(described_class::BaseAction).to eq(
        ForestAdminDatasourceCustomizer::Decorators::Action::BaseAction
      )
    end

    it 'exports ComputedDefinition' do
      expect(described_class::ComputedDefinition).to eq(
        ForestAdminDatasourceCustomizer::Decorators::Computed::ComputedDefinition
      )
    end

    it 'exports ActionContext' do
      expect(described_class::ActionContext).to eq(
        ForestAdminDatasourceCustomizer::Decorators::Action::Context::ActionContext
      )
    end

    it 'exports ActionContextSingle' do
      expect(described_class::ActionContextSingle).to eq(
        ForestAdminDatasourceCustomizer::Decorators::Action::Context::ActionContextSingle
      )
    end

    it 'exports ActionResultBuilder' do
      expect(described_class::ActionResultBuilder).to eq(
        ForestAdminDatasourceCustomizer::Decorators::Action::ResultBuilder
      )
    end

    it 'exports ChartResultBuilder' do
      expect(described_class::ChartResultBuilder).to eq(
        ForestAdminDatasourceCustomizer::Decorators::Chart::ResultBuilder
      )
    end

    it 'exports Caller' do
      expect(described_class::Caller).to eq(
        ForestAdminDatasourceToolkit::Components::Caller
      )
    end

    it 'exports Plugin' do
      expect(described_class::Plugin).to eq(
        ForestAdminDatasourceCustomizer::Plugins::Plugin
      )
    end

    it 'exports ConditionTreeFactory' do
      expect(described_class::ConditionTreeFactory).to eq(
        ForestAdminDatasourceToolkit::Components::Query::ConditionTree::ConditionTreeFactory
      )
    end

    it 'exports FilterFactory' do
      expect(described_class::FilterFactory).to eq(
        ForestAdminDatasourceToolkit::Components::Query::FilterFactory
      )
    end

    it 'exports ProjectionFactory' do
      expect(described_class::ProjectionFactory).to eq(
        ForestAdminDatasourceToolkit::Components::Query::ProjectionFactory
      )
    end

    it 'exports SortFactory' do
      expect(described_class::SortFactory).to eq(
        ForestAdminDatasourceToolkit::Components::Query::SortUtils::SortFactory
      )
    end

    it 'exports ChartContext' do
      expect(described_class::ChartContext).to eq(
        ForestAdminDatasourceCustomizer::Decorators::Chart::ChartContext
      )
    end

    it 'exports HookContext' do
      expect(described_class::HookContext).to eq(
        ForestAdminDatasourceCustomizer::Decorators::Hook::Context::HookContext
      )
    end

    it 'exports BusinessError' do
      expect(described_class::BusinessError).to eq(
        ForestAdminAgent::Http::Exceptions::BusinessError
      )
    end

    it 'exports ValidationError' do
      expect(described_class::ValidationError).to eq(
        ForestAdminAgent::Http::Exceptions::ValidationError
      )
    end

    it 'exports ForbiddenError' do
      expect(described_class::ForbiddenError).to eq(
        ForestAdminAgent::Http::Exceptions::ForbiddenError
      )
    end

    it 'exports UnauthorizedError' do
      expect(described_class::UnauthorizedError).to eq(
        ForestAdminAgent::Http::Exceptions::UnauthorizedError
      )
    end

    it 'exports NotFoundError' do
      expect(described_class::NotFoundError).to eq(
        ForestAdminAgent::Http::Exceptions::NotFoundError
      )
    end

    it 'exports UnprocessableError' do
      expect(described_class::UnprocessableError).to eq(
        ForestAdminAgent::Http::Exceptions::UnprocessableError
      )
    end

    it 'exports BadRequestError' do
      expect(described_class::BadRequestError).to eq(
        ForestAdminAgent::Http::Exceptions::BadRequestError
      )
    end
  end

  describe 'when included in a class' do
    let(:test_class) do
      Class.new do
        include ForestAdmin::Types
      end
    end

    it 'makes Filter accessible without prefix' do
      expect(test_class::Filter).to eq(ForestAdminDatasourceToolkit::Components::Query::Filter)
    end

    it 'makes ConditionTreeLeaf accessible without prefix' do
      expect(test_class::ConditionTreeLeaf).to eq(
        ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf
      )
    end

    it 'makes Operators accessible without prefix' do
      expect(test_class::Operators).to eq(
        ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators
      )
    end

    it 'allows creating a ConditionTreeLeaf instance' do
      leaf = test_class::ConditionTreeLeaf.new('status', test_class::Operators::EQUAL, 'active')
      expect(leaf.field).to eq('status')
      expect(leaf.operator).to eq('equal')
      expect(leaf.value).to eq('active')
    end

    it 'allows creating a Filter instance' do
      filter = test_class::Filter.new
      expect(filter).to be_a(ForestAdminDatasourceToolkit::Components::Query::Filter)
    end

    it 'allows creating an Aggregation instance' do
      aggregation = test_class::Aggregation.new(operation: 'Count')
      expect(aggregation.operation).to eq('Count')
    end

    it 'makes new classes accessible without prefix' do
      expect(test_class::ActionContext).to eq(
        ForestAdminDatasourceCustomizer::Decorators::Action::Context::ActionContext
      )
      expect(test_class::ActionResultBuilder).to eq(
        ForestAdminDatasourceCustomizer::Decorators::Action::ResultBuilder
      )
      expect(test_class::ChartResultBuilder).to eq(
        ForestAdminDatasourceCustomizer::Decorators::Chart::ResultBuilder
      )
      expect(test_class::Caller).to eq(
        ForestAdminDatasourceToolkit::Components::Caller
      )
      expect(test_class::Plugin).to eq(
        ForestAdminDatasourceCustomizer::Plugins::Plugin
      )
    end

    it 'allows creating a Caller instance' do
      caller = test_class::Caller.new(
        id: 1,
        email: 'test@example.com',
        first_name: 'Test',
        last_name: 'User',
        team: 'Operations',
        rendering_id: 123,
        tags: {},
        timezone: 'UTC',
        permission_level: 'admin'
      )
      expect(caller.email).to eq('test@example.com')
      expect(caller.timezone).to eq('UTC')
    end

    it 'allows creating ActionResultBuilder and ChartResultBuilder instances' do
      action_result_builder = test_class::ActionResultBuilder.new
      expect(action_result_builder).to be_a(ForestAdminDatasourceCustomizer::Decorators::Action::ResultBuilder)

      chart_result_builder = test_class::ChartResultBuilder.new
      expect(chart_result_builder).to be_a(ForestAdminDatasourceCustomizer::Decorators::Chart::ResultBuilder)
    end

    it 'makes factory classes accessible without prefix' do
      expect(test_class::ConditionTreeFactory).to eq(
        ForestAdminDatasourceToolkit::Components::Query::ConditionTree::ConditionTreeFactory
      )
      expect(test_class::FilterFactory).to eq(
        ForestAdminDatasourceToolkit::Components::Query::FilterFactory
      )
      expect(test_class::ProjectionFactory).to eq(
        ForestAdminDatasourceToolkit::Components::Query::ProjectionFactory
      )
      expect(test_class::SortFactory).to eq(
        ForestAdminDatasourceToolkit::Components::Query::SortUtils::SortFactory
      )
    end

    it 'allows using ConditionTreeFactory methods' do
      # Test from_plain_object
      tree = test_class::ConditionTreeFactory.from_plain_object(
        { field: 'status', operator: 'equal', value: 'active' }
      )
      expect(tree).to be_a(test_class::ConditionTreeLeaf)
      expect(tree.field).to eq('status')
      expect(tree.operator).to eq('equal')
      expect(tree.value).to eq('active')

      # Test intersect
      tree1 = test_class::ConditionTreeLeaf.new('status', 'equal', 'active')
      tree2 = test_class::ConditionTreeLeaf.new('age', 'greater_than', 18)
      combined = test_class::ConditionTreeFactory.intersect([tree1, tree2])
      expect(combined).to be_a(test_class::ConditionTreeBranch)
      expect(combined.aggregator).to eq('And')
      expect(combined.conditions.size).to eq(2)

      # Test union
      unioned = test_class::ConditionTreeFactory.union([tree1, tree2])
      expect(unioned).to be_a(test_class::ConditionTreeBranch)
      expect(unioned.aggregator).to eq('Or')
      expect(unioned.conditions.size).to eq(2)

      # Test match_none
      none = test_class::ConditionTreeFactory.match_none
      expect(none).to be_a(test_class::ConditionTreeBranch)
    end

    it 'makes context and exception classes accessible' do
      expect(test_class::ChartContext).to eq(
        ForestAdminDatasourceCustomizer::Decorators::Chart::ChartContext
      )
      expect(test_class::HookContext).to eq(
        ForestAdminDatasourceCustomizer::Decorators::Hook::Context::HookContext
      )
      expect(test_class::BusinessError).to eq(
        ForestAdminAgent::Http::Exceptions::BusinessError
      )
      expect(test_class::ValidationError).to eq(
        ForestAdminAgent::Http::Exceptions::ValidationError
      )
    end

    it 'allows creating and catching ValidationError' do
      error = test_class::ValidationError.new('Invalid input', details: { field: 'email' })
      expect(error.message).to eq('Invalid input')
      expect(error.details).to eq({ field: 'email' })
      expect(error.name).to eq('ValidationError')

      expect { raise error }.to raise_error(test_class::ValidationError)
    end

    it 'allows creating and catching ForbiddenError' do
      error = test_class::ForbiddenError.new('Access denied')
      expect(error.message).to eq('Access denied')
      expect(error.name).to eq('ForbiddenError')

      expect { raise error }.to raise_error(test_class::ForbiddenError)
    end

    it 'allows creating and catching UnprocessableError' do
      error = test_class::UnprocessableError.new('Cannot process')
      expect(error.message).to eq('Cannot process')

      expect { raise error }.to raise_error(test_class::UnprocessableError)
    end

    it 'allows exception inheritance hierarchy' do
      # ValidationError should be a BusinessError
      expect(test_class::ValidationError.new).to be_a(test_class::BusinessError)
      expect(test_class::ForbiddenError.new).to be_a(test_class::BusinessError)
      expect(test_class::NotFoundError.new('Not found')).to be_a(test_class::BusinessError)
    end
  end
end
