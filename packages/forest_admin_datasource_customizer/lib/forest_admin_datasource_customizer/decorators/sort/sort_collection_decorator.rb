module ForestAdminDatasourceCustomizer
  module Decorators
    module Sort
      class SortCollectionDecorator < ForestAdminDatasourceToolkit::Decorators::CollectionDecorator
        include ForestAdminDatasourceToolkit::Exceptions
        include ForestAdminDatasourceToolkit::Validations
        include ForestAdminDatasourceToolkit::Components::Query
        include ForestAdminDatasourceToolkit::Utils

        attr_reader :sorts

        def initialize(child_collection, datasource)
          super
          @sorts = {}
        end

        def emulate_field_sorting(name)
          replace_or_emulate_field_sorting(name, nil)
        end

        def replace_field_sorting(name, equivalent_sort)
          if equivalent_sort.nil?
            raise ForestException, 'A new sorting method should be provided to replace field sorting'
          end

          replace_or_emulate_field_sorting(name, equivalent_sort)
        end

        def list(caller, filter = nil, projection = nil)
          child_filter = filter.override(sort: filter.sort&.replace_clauses do |clause|
                                                 rewrite_plain_sort_clause(clause)
                                               end)

          if child_filter.sort.nil? || child_filter.sort.none? { |clause| emulated?(clause[:field]) }
            return child_collection.list(caller, child_filter, projection)
          end

          # Fetch the whole collection, but only with the fields we need to sort
          reference_records = child_collection.list(caller, child_filter.override(sort: nil, page: nil),
                                                    child_filter.sort.projection.with_pks(self))
          reference_records = child_filter.sort.apply(reference_records)
          reference_records = child_filter.page.apply(reference_records) if child_filter.page

          # We now have the information we need to sort by the field
          new_filter = Filter.new(condition_tree: ConditionTree::ConditionTreeFactory.match_records(self,
                                                                                                    reference_records))

          records = child_collection.list(caller, new_filter, projection.clone.with_pks(self))
          records = sort_records(reference_records, records)

          projection.apply(records)
        end

        # Only a field registered through `emulate_field_sorting` or
        # `replace_field_sorting` becomes sortable here: those are the ones
        # `list` above knows how to order, either by emulating the sort over the
        # whole collection or by rewriting it into an equivalent one. Every other
        # field keeps the flag its datasource declared -- a clause on it is
        # handed straight to `child_collection.list`, so marking it sortable
        # would let the UI ask for an order nothing honours, and the records
        # would come back in whatever order the datasource imposes.
        #
        # `@sorts` holds nil as the value of an emulated field, so membership is
        # read with `key?`, the way `emulated?` reads it.
        #
        # `CollectionDecorator#schema` only shallow-copies the schema it hands
        # over, so the fields hash and the ColumnSchema objects in it are the
        # ones of the collection below: both are copied before the flag is set,
        # or the decorator would rewrite the schema of its own child.
        def refine_schema(child_schema)
          schema = child_schema.dup
          schema[:fields] = child_schema[:fields].dup

          schema[:fields].each do |name, field|
            next unless field.type == 'Column' && @sorts.key?(name)

            schema[:fields][name] = field.dup.tap { |sortable| sortable.is_sortable = true }
          end

          schema
        end

        def rewrite_plain_sort_clause(clause)
          # Order by is targeting a field on another collection => recurse.
          if clause[:field].include?(':')
            prefix = clause[:field].split(':')[0]
            schema = self.schema[:fields][prefix]
            association = datasource.get_collection(schema.foreign_collection)

            return ForestAdminDatasourceToolkit::Components::Query::Sort.new([clause])
                                                                        .unnest
                                                                        .replace_clauses { |sub_clause| association.rewrite_plain_sort_clause(sub_clause) }
                                                                        .nest(prefix)
          end

          # Field that we own: recursively replace using equivalent sort
          equivalent_sort = @sorts[clause[:field]]

          if equivalent_sort
            equivalent_sort = equivalent_sort.inverse unless clause[:ascending]

            return equivalent_sort.replace_clauses { |sub_clause| rewrite_plain_sort_clause(sub_clause) }
          end

          ForestAdminDatasourceToolkit::Components::Query::Sort.new([clause])
        end

        def emulated?(path)
          index = path.index(':')
          return @sorts.key?(path) if index.nil?

          foreign_collection = schema[:fields][path[0, index]].foreign_collection
          association = datasource.get_collection(foreign_collection)

          association.emulated?(path[index + 1, path.length - index - 1])
        end

        private

        def replace_or_emulate_field_sorting(name, equivalent_sort)
          FieldValidator.validate(self, name)
          @sorts[name.to_s] =
            equivalent_sort ? ForestAdminDatasourceToolkit::Components::Query::Sort.new(equivalent_sort) : nil
          mark_schema_as_dirty
        end

        def sort_records(reference_records, records)
          position_by_id = {}
          sorted = Array.new(records.length)

          reference_records.each_with_index do |record, index|
            position_by_id[Record.primary_keys(self, record).join('|')] = index
          end

          records.each do |record|
            id = Record.primary_keys(self, record).join('|')
            sorted[position_by_id[id]] = record
          end

          sorted
        end
      end
    end
  end
end
