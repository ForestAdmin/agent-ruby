# This file contains code to create and configure your Forest Admin agent
# You can customize this file according to your needs

module ForestAdminRpcAgent
  class CreateRpcAgent
    include ForestAdminDatasourceToolkit::Components::Query
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

    def self.setup!
      datasource = ForestAdminDatasourceActiveRecord::Datasource.new(Rails.env.to_sym)

      agent = ForestAdminRpcAgent::Agent.instance
                                .add_datasource(datasource)


      agent.customize_collection('Product') do |collection|
        collection.add_chart('groupByManufacturer') do |context, result_builder|
          aggregation = Aggregation.new(operation: 'Count', field: 'manufacturer:id')
          filter = Filter.new(
            condition_tree: Nodes::ConditionTreeBranch.new(
              'And',
              [
                Nodes::ConditionTreeLeaf.new('manufacturer:id', Operators::PRESENT),
              ]
            )
          )
          result = context.collection.aggregate(filter, aggregation)

          result_builder.value(result[0]['value']).to_json
        end
      end

      # @agent.add_chart('appointments') do |_context, result_builder|
      #   result_builder.value(784, 760)
      # end

      agent.build

    end
  end
end
