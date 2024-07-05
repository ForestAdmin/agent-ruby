module ForestAdminDatasourceCustomizer
  module Decorators
    module Computed
      module Utils
        class ComputedField
          include ForestAdminDatasourceToolkit::Components::Query

          def self.compute_field(ctx, computed, computed_dependencies, flatten)
            transform_unique_values(
              Flattener.un_flatten(
                flatten,
                Projection.new(computed_dependencies)
              ),
              ->(unique_partials) { computed.get_values(unique_partials, ctx) }
            )
          end

          def self.queue_field(ctx, collection, new_path, paths, flatten)
            return if paths.include?(new_path)

            computed = collection.get_computed(new_path)
            computed_dependencies = Flattener.with_null_marker(computed.dependencies)
            nested_dependencies = Projection.new(computed_dependencies)
                                            .nest(prefix: new_path.include?(':') ? new_path.split(':')[0] : nil)

            nested_dependencies.each do |path|
              queue_field(ctx, collection, path, paths, flatten)
            end

            dependency_values = nested_dependencies.map { |path| flatten[paths.index(path)] }

            paths.push(new_path)

            flatten << compute_field(ctx, computed, computed_dependencies, dependency_values)
          end

          def self.compute_from_records(ctx, collection, records_projection, desired_projection, records)
            paths = Flattener.with_null_marker(records_projection)
            flatten = Flattener.flatten(records, paths)

            desired_projection.each do |path|
              queue_field(ctx, collection, path, paths, flatten)
            end

            final_projection = Flattener.with_null_marker(desired_projection)

            Flattener.un_flatten(final_projection.map { |path| flatten[paths.index(path)] }, final_projection)
          end

          def self.transform_unique_values(inputs, callback)
            indexes = {}
            mapping = []
            unique_inputs = []

            inputs.each do |input|
              if input
                hash = Digest::SHA1.hexdigest(input.to_s)

                if indexes[hash].nil?
                  indexes[hash] = unique_inputs.length
                  unique_inputs.push(input)
                end

                mapping.push(indexes[hash])
              else
                mapping.push(-1)
              end
            end

            unique_outputs = callback.call(unique_inputs)

            mapping.map { |index| index == -1 ? nil : unique_outputs[index] }
          end
        end
      end
    end
  end
end
