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
          new_filter = Filter.new(condition_tree: ConditionTree::ConditionTreeFactory.match_records(schema,
                                                                                                    reference_records))

          records = child_collection.list(caller, new_filter, projection.with_pks(self))
          records = sort_records(reference_records, records)

          projection.apply(records)
        end

        def refine_schema(child_schema)
          child_schema[:fields].each do |name, schema|
            if schema.type == 'Column'
              schema.is_sortable = true if @sorts[name].nil?
              child_schema[:fields][name] = schema
            end
          end

          child_schema
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
          return @sorts[path] if index.nil?

          foreign_collection = schema[:fields][path[0, index]].foreign_collection
          association = datasource.get_collection(foreign_collection)

          association.emulated?(path[index + 1, path.length - index - 1])
        end

        private

        def replace_or_emulate_field_sorting(name, equivalent_sort)
          FieldValidator.validate(self, name)
          @sorts[name] =
            equivalent_sort ? ForestAdminDatasourceToolkit::Components::Query::Sort.new(equivalent_sort) : nil
          mark_schema_as_dirty
        end

        def sort_records(reference_records, records)
          position_by_id = {}
          sorted = Array.new(records.length)

          reference_records.each_with_index do |record, index|
            position_by_id[Record.primary_keys(schema, record).join('|')] = index
          end

          records.each do |record|
            id = Record.primary_keys(schema, record).join('|')
            sorted[position_by_id[id]] = record
          end

          sorted
        end
      end
    end
  end
end
