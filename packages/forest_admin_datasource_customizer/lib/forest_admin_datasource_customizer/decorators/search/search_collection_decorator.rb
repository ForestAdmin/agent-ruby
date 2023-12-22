module ForestAdminDatasourceCustomizer
  module Decorators
    module Search
      class SearchCollectionDecorator < ForestAdminDatasourceToolkit::Decorators::CollectionDecorator
        include ForestAdminDatasourceToolkit::Schema
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

        def initialize(child_collection, datasource)
          super
          @replacer = nil
        end

        def replace_search(replacer)
          @replacer = replacer
        end

        def refine_schema(sub_schema)
          sub_schema.merge({ searchable: true })
        end

        def refine_filter(caller, filter)
          # Search string is not significant
          return filter.override({ search: nil }) if !filter || !filter.search || filter.search.strip&.length&.zero?

          # Implement search ourselves
          if @replacer || !@child_collection.schema[:searchable]
            ctx = ForestAdminDatasourceCustomizer::Context::CollectionCustomizationContext.new(self, caller)
            tree = default_replacer(filter.search, filter.search_extended)

            if @replacer
              plain_tree = @replacer.call(filter.search, filter.search_extended, ctx)
              tree = ConditionTreeFactory.from_plain_object(plain_tree)
            end

            # Note that if no fields are searchable with the provided searchString, the conditions
            # array might be empty, which will create a condition returning zero records
            # (this is the desired behavior).
            return filter.override({
                                     condition_tree: ConditionTreeFactory.intersect([filter.condition_tree, tree]),
                                     search: nil
                                   })
          end

          # Let sub-collection deal with the search
          filter
        end

        private

        def default_replacer(search, extended)
          searchable_fields = self.class.get_fields(@child_collection, extended)

          conditions = searchable_fields.map do |field, schema|
            self.class.build_condition(field, schema, search)
          end

          ConditionTreeFactory.union(conditions)
        end

        # class << self
        #   private
        def self.build_condition(field, schema, search_string)
          column_type = schema.column_type
          enum_values = schema.enum_values
          filter_operators = schema.filter_operators
          is_number = search_string.to_i.to_s == search_string
          is_uuid = uuid?(search_string)

          if column_type == PrimitiveType::NUMBER && is_number && filter_operators&.include?(Operators::EQUAL)
            return Nodes::ConditionTreeLeaf.new(field, Operators::EQUAL, search_string.to_i)
          end

          if column_type == PrimitiveType::ENUM && filter_operators&.include?(Operators::EQUAL)
            search_value = lenient_find(enum_values, search_string)

            return Nodes::ConditionTreeLeaf.new(field, Operators::EQUAL, search_value) if search_value
          end

          if column_type == PrimitiveType::STRING
            is_case_sensitive = !search_string.casecmp(search_string).zero?
            supports_i_contains = filter_operators&.include?(Operators::I_CONTAINS)
            supports_contains = filter_operators&.include?(Operators::CONTAINS)
            supports_equal = filter_operators&.include?(Operators::EQUAL)

            operator = nil
            if supports_i_contains && (is_case_sensitive || !supports_contains)
              operator = Operators::I_CONTAINS
            elsif supports_contains
              operator = Operators::CONTAINS
            elsif supports_equal
              operator = Operators::EQUAL
            end

            return Nodes::ConditionTreeLeaf.new(field, operator, search_string) if operator
          end

          if column_type == PrimitiveType::UUID && is_uuid && filter_operators&.include?(Operators::EQUAL)
            return Nodes::ConditionTreeLeaf.new(field, Operators::EQUAL, search_string)
          end

          nil
        end

        def self.get_fields(collection, extended)
          fields = []
          collection.schema[:fields].each do |name, field|
            fields.push([name, field]) if field.type == 'Column'

            next unless extended && (field.type == 'ManyToOne' || field.type == 'OneToOne')

            related = collection.datasource.get_collection(field.foreign_collection)

            related.schema[:fields].each do |sub_name, sub_field|
              fields.push(["#{name}:#{sub_name}", sub_field]) if sub_field.type == 'Column'
            end
          end

          fields
        end

        def self.lenient_find(haystack, needle)
          haystack&.find { |v| v == needle.strip } || haystack&.find { |v| v.downcase == needle.downcase.strip }
        end

        def self.uuid?(value)
          value.to_s.downcase.match?(/^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i)
        end
        # end
      end
    end
  end
end
