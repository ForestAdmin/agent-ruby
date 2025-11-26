# This file contains code to create and configure your Forest Admin agent
# You can customize this file according to your needs

module ForestAdminRpcAgent
  class CreateRpcAgent
    # Single include brings all commonly-used Forest Admin types
    include ForestAdmin::Types

    def self.setup!
      datasource = ForestAdminDatasourceActiveRecord::Datasource.new(Rails.env.to_sym)

      agent = ForestAdminRpcAgent::Agent.instance.add_datasource(datasource)

      agent.customize_collection('Product') do |collection|
        collection.add_chart('groupByManufacturer') do |context, result_builder|
          aggregation = Aggregation.new(operation: 'Count', field: 'manufacturer:id')
          filter = Filter.new(
            condition_tree: ConditionTreeBranch.new(
              'And',
              [
                ConditionTreeLeaf.new('manufacturer:id', Operators::PRESENT),
              ]
            )
          )
          result = context.collection.aggregate(filter, aggregation)

          result_builder.value(result[0]['value']).to_json
        end

        collection.add_action(
          'add product',
          BaseAction.new(
            scope: ActionScope::SINGLE,
            form: [
              {
                type: FieldType::NUMBER,
                label: 'amount',
                description: 'The amount (USD) to charge the credit card. Example: 42.50',
                is_required: true
              },
              {
                type: FieldType::STRING,
                label: 'label',
              },
              {
                if_condition: proc { true },
                label: 'product picture',
                type: FieldType::FILE,
                widget: 'FilePicker',
                extensions: %w[png jpg],
                max_size_mb: 20,
                default_value: proc { File.new(File.dirname(__FILE__) + '/../../app/assets/images/tree.png') },
            }
            ]
          ) do |context, result_builder|
            # form_values = context.form_values

            # ... Do your stuff ...

            result_builder.success(message: 'Product add!')
          end
        )
      end

      agent.add_chart('appointments') do |_context, result_builder|
        result_builder.value(784, 760)
      end

      agent.build
    end
  end
end
