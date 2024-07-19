module ForestAdminDatasourceCustomizer
  module Decorators
    module Computed
      class ComputeCollectionDecorator < ForestAdminDatasourceToolkit::Decorators::CollectionDecorator
        include ForestAdminDatasourceToolkit::Components::Query
        include ForestAdminDatasourceToolkit::Validations
        include ForestAdminDatasourceCustomizer::Decorators::Computed::Utils
        include ForestAdminDatasourceToolkit::Exceptions

        def initialize(child_collection, datasource)
          super
          @computeds = {}
        end

        def get_computed(path)
          index = path.index(':')
          return @computeds[path] if index.nil?
          return @computeds[path] if schema[:fields][path[0, index]].type == 'PolymorphicManyToOne'

          foreign_collection = schema[:fields][path[0, index]].foreign_collection
          association = @datasource.get_collection(foreign_collection)

          association.get_computed(path[index + 1, path.length - index - 1])
        end

        def register_computed(name, computed)
          FieldValidator.validate_name(@name, name)

          # Check that all dependencies exist and are columns
          computed.dependencies.each do |field|
            FieldValidator.validate(self, field)
            if field.include?(':') && schema[:fields][field.partition(':')[0]].type == 'PolymorphicManyToOne'
              raise ForestException,
                    "Dependencies over a polymorphic relations(#{self.name}.#{field.partition(":")[0]}) is forbidden"
            end
          end

          if computed.dependencies.length <= 0
            raise ForestException,
                  "Computed field '#{name}' must have at least one dependency."
          end

          @computeds[name] = computed
          mark_schema_as_dirty
        end

        def list(caller, filter, projection)
          child_projection = projection.replace { |path| rewrite_field(self, path) }
          records = @child_collection.list(caller, filter, child_projection)
          return records if child_projection.equals(projection)

          context = ForestAdminDatasourceCustomizer::Context::CollectionCustomizationContext.new(self, caller)

          ComputedField.compute_from_records(context, self, child_projection, projection, records)
        end

        def aggregate(caller, filter, aggregation, limit = nil)
          # No computed are used in the aggregation => just delegate to the underlying collection.
          unless aggregation.projection.any? do |field|
                   get_computed(field)
                 end
            return @child_collection.aggregate(caller, filter, aggregation,
                                               limit)
          end

          # Fallback to full emulation.
          aggregation.apply(
            list(caller, filter, aggregation.projection),
            caller.timezone,
            limit
          )
        end

        def refine_schema(child_schema)
          schema = child_schema.clone
          schema[:fields] = child_schema[:fields].clone

          @computeds.each do |name, computed|
            schema[:fields][name] = ForestAdminDatasourceToolkit::Schema::ColumnSchema.new(
              column_type: computed.column_type,
              default_value: computed.default_value,
              enum_values: computed.enum_values || [],
              filter_operators: [],
              is_primary_key: false,
              is_read_only: true,
              is_sortable: false
            )
          end

          schema
        end

        def rewrite_field(collection, path)
          # Projection is targeting a field on another collection => recurse.
          if path.include?(':')
            prefix = path.split(':')[0]
            schema = collection.schema[:fields][prefix]
            if schema.type != 'PolymorphicManyToOne'
              association = collection.datasource.get_collection(schema.foreign_collection)

              return Projection.new([path])
                               .unnest
                               .replace { |sub_path| rewrite_field(association, sub_path) }
                               .nest(prefix: prefix)
            end
          end

          # Computed field that we own: recursively replace by dependencies
          computed = collection.get_computed(path)

          if computed
            Projection.new(computed.dependencies.flatten).replace do |dep_path|
              rewrite_field(collection, dep_path)
            end
          else
            Projection.new([path])
          end
        end
      end
    end
  end
end
