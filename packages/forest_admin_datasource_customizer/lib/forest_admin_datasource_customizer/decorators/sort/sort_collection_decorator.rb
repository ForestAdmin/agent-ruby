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

          if child_filter.sort&.none? { |field| emulated?(field) }
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
          # const fields: Record<string, FieldSchema> = {};
          #
          #     for (const [name, schema] of Object.entries(childSchema.fields)) {
          #       if (schema.type === 'Column') {
          #         let sortable = schema.isSortable;
          #
          #         if (this.disabledSorts.has(name)) {
          #           // disableFieldSorting
          #           sortable = false;
          #         } else if (this.sorts.has(name)) {
          #           // replaceFieldSorting
          #           sortable = true;
          #         }
          #
          #         fields[name] = { ...schema, isSortable: sortable };
          #       } else {
          #         fields[name] = schema;
          #       }
          #     }
          #
          #     return { ...childSchema, fields };
          fields = {}

          child_schema[:fields].each do |name, schema|
            if schema.type == 'Column'
              sortable = schema.is_sortable
              sortable = true unless @sorts[name].nil?
              fields[name] = schema.merge(is_sortable: sortable)
            else
              fields[name] = schema
            end
          end

          child_schema.merge(fields: fields)
        end

        private

        def replace_or_emulate_field_sorting(name, equivalent_sort)
          FieldValidator.validate(self, name)
          @sorts[name] = equivalent_sort.nil? ? nil : Sort.new(equivalent_sort) ## ARRAY
          mark_schema_as_dirty
        end

        # private sortRecords(referenceRecords: RecordData[], records: RecordData[]): RecordData[] {
        #     const positionById: Record<string, number> = {};
        #     const sorted = new Array(records.length);
        #
        #     for (const [index, record] of referenceRecords.entries()) {
        #       positionById[RecordUtils.getPrimaryKey(this.schema, record).join('|')] = index;
        #     }
        #
        #     for (const record of records) {
        #       const id = RecordUtils.getPrimaryKey(this.schema, record).join('|');
        #       sorted[positionById[id]] = record;
        #     }
        #
        #     return sorted;
        #   }
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

        # private rewritePlainSortClause(clause: PlainSortClause): Sort {
        #     // Order by is targeting a field on another collection => recurse.
        #     if (clause.field.includes(':')) {
        #       const [prefix] = clause.field.split(':');
        #       const schema = this.schema.fields[prefix] as RelationSchema;
        #       const association = this.dataSource.getCollection(schema.foreignCollection);
        #
        #       return new Sort(clause)
        #         .unnest()
        #         .replaceClauses(subClause => association.rewritePlainSortClause(subClause))
        #         .nest(prefix);
        #     }
        #
        #     // Field that we own: recursively replace using equivalent sort
        #     let equivalentSort = this.sorts.get(clause.field);
        #
        #     if (equivalentSort) {
        #       if (!clause.ascending) equivalentSort = equivalentSort.inverse();
        #
        #       return equivalentSort.replaceClauses(subClause => this.rewritePlainSortClause(subClause));
        #     }
        #
        #     return new Sort(clause);
        #   }

        def rewrite_plain_sort_clause(clause)
          # Order by is targeting a field on another collection => recurse.
          if clause[:field].include?(':')
            prefix = clause[:field].split(':')[0]
            schema = self.schema[:fields][prefix]
            association = datasource.get_collection(schema.foreign_collection)

            return Sort.new(clause)
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

          Sort.new(clause)
        end

        #   private isEmulated(path: string): boolean {
        #     const index = path.indexOf(':');
        #     if (index === -1) return this.sorts.has(path);
        #
        #     const { foreignCollection } = this.schema.fields[path.substring(0, index)] as RelationSchema;
        #     const association = this.dataSource.getCollection(foreignCollection);
        #
        #     return association.isEmulated(path.substring(index + 1));
        #   }
        def emulated?(path)
          index = path.index(':')
          return @sorts.key?(path) if index.nil?

          foreign_collection = schema[:fields][path[0, index]][:foreign_collection]
          association = datasource.get_collection(foreign_collection)

          association.emulated?(path[index + 1, path.length - index - 1])
        end
      end
    end
  end
end
