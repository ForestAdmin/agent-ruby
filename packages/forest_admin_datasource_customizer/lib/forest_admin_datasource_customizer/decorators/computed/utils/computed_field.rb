module ForestAdminDatasourceCustomizer
  module Decorators
    module Computed
      class ComputedField
        include ForestAdminDatasourceToolkit::Components::Query

        def compute_field(ctx, computed, computed_dependencies, flatten)
          transform_unique_values(
            Flattener.un_flatten(flatten, Projection.new(computed_dependencies)),
            ->(unique_partials) { computed.get_values(unique_partials, ctx) }
          )
        end

        def queue_field(ctx, collection, new_path, paths, flatten)
          return if paths.include?(new_path)

          computed = collection.get_computed(new_path)
          nested_dependencies = Projection.new(computed[:dependencies])
                                          .nest(prefix: new_path.include?(':') ? new_path.split(':')[0] : nil)

          nested_dependencies.each do |path|
            queue_field(ctx, collection, path, paths, flatten)
          end

          dependency_values = nested_dependencies.map { |path| flatten[paths.search(path)] }
          paths.push(new_path)

          flatten << compute_field(ctx, computed, computed[:dependencies], dependency_values)
        end

        def compute_from_records(ctx, collection, records_projection, desired_projection, records)
          paths = records_projection.clone
          flatten = Flattener.flatten(records, paths)

          desired_projection.each do |path|
            queue_field(ctx, collection, path, paths, flatten)
          end

          Flattener.un_flatten(desired_projection.map { |path| flatten[paths.search(path)] }, desired_projection)
        end
      end
    end
  end
end
