module ForestAdminDatasourceCustomizer
  module Decorators
    module OperatorsEmulate
      class OperatorsEmulateCollectionDecorator < ForestAdminDatasourceToolkit::Decorators::CollectionDecorator
        include ForestAdminDatasourceToolkit
        include ForestAdminDatasourceToolkit::Decorators
        include ForestAdminDatasourceToolkit::Components::Query
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

        @fields = {}

        def emulate_field_operator(name, operator)
          replace_field_operator(name, operator)
        end

        def replace_field_operator(name, operator, &replace_by)
          # Check that the collection can actually support our rewriting
          pks = Utils::Schema.primary_keys(child_collection)
          pks.each do |pk|
            schema = child_collection.schema[:fields][pk]
            operators = schema.filter_operators

            if !operators.include?(Operators::EQUAL) || !operators.include?(Operators::IN)
              raise Exceptions::ForestException, "Cannot override operators on collection #{self.name}:
                the primary key columns must support 'Equal' and 'In' operators."
            end
          end

          # Check that targeted field is valid
          field = child_collection.schema[:fields][name]
          Validations::FieldValidator.validate(self, name)
          raise Exceptions::ForestException, 'Cannot override operators on co' unless field.nil?

          # Mark the field operator as replaced.
          fields[name] = {} unless fields.key?(name)
          fields[name].merge({ operator => replace_by })
          mark_schema_as_dirty
        end

        protected

        def refine_schema(sub_schema)
          sub_schema[:fields].map do |name, schema|
            schema.filter_operators = schema.filter_operators.union(fields[name].keys) if fields.key?(name)
          end

          sub_schema
        end

        def refine_filter(caller, filter = nil)
          filter&.override(
            condition_tree: filter.condition_tree&.replace_leafs do |leaf|
              replace_leaf(caller, leaf, [])
            end
          )
        end

        def replace_leaf(caller, leaf, replacements)
          # ConditionTree is targeting a field on another collection => recurse.
          if leaf.field.include?(':')
            prefix = leaf.field.split(':').first
            schema = schema[:fields][prefix]
            association = datasource.get_collection(schema.foreign_collection)
            association_leaf = leaf.unnest.replace_leafs do |sub_leaf|
              association.replace_leaf(caller, sub_leaf, replacements)
            end

            return association_leaf.nest(prefix)
          end

          fields[leaf.field]&.key?(leaf.operator) ? compute_equivalent(caller, leaf, replacements) : leaf
        end

        def compute_equivalent(caller, leaf, replacements)
          handler = fields.dig(leaf.field, leaf.operator)
          if handler
            replacement_id = "#{name}.#{leaf.field}[#{leaf.operator}]"
            sub_replacements = [...replacements, replacement_id]
            if replacements.include?(replacement_id)
              raise Exceptions::ForestException, "Operator replacement cycle: #{sub_replacements.join(" -> ")}"
            end

            result = handler.call(leaf.value, Context::CollectionCustomizationContext.new(self, caller))

            if result
              equivalent = result.is_a?(ConditionTree) ? result : ConditionTreeFactory.from_plain_object(result)
              equivalent.replace_leafs do |sub_leaf|
                replace_leaf(caller, sub_leaf, sub_replacements)
              end

              # TODO : add ConditionTreeValidator
              # ConditionTreeValidator.validate(equivalent, this);

              return equivalent
            end
          end

          ConditionTreeFactory.match_records(
            schema,
            leaf.apply(
              list(caller, Filter.new, leaf.projection.with_pks(self)),
              self,
              caller.timezone
            )
          )
        end
      end
    end
  end
end
