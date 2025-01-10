module ForestAdminDatasourceCustomizer
  module Decorators
    module Search
      class SearchCollectionDecorator < ForestAdminDatasourceToolkit::Decorators::CollectionDecorator
        include ForestAdminDatasourceToolkit::Schema
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

        def initialize(child_collection, datasource)
          super
          @replacer = nil
          @disabled_search = get_fields(false).empty?
        end

        def disable_search
          @disabled_search = true
        end

        def replace_search(replacer)
          @replacer = replacer
        end

        def refine_schema(sub_schema)
          sub_schema.merge({ searchable: !@disabled_search })
        end

        def refine_filter(caller, filter)
          # Search string is not significant
          return filter.override({ search: nil }) if !filter || !filter.search || filter.search.strip&.empty?

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
          searchable_fields = get_fields(extended)

          conditions = searchable_fields.map do |field, schema|
            build_condition(field, schema, search)
          end

          ConditionTreeFactory.union(conditions)
        end

        def build_condition(field, schema, search_string)
          column_type = schema.column_type
          enum_values = schema.enum_values
          filter_operators = schema.filter_operators
          is_number = number?(search_string)
          is_uuid = uuid?(search_string)

          if column_type == PrimitiveType::NUMBER && is_number
            return Nodes::ConditionTreeLeaf.new(field, Operators::EQUAL, search_string.to_f)
          end

          if column_type == PrimitiveType::ENUM
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

          if column_type == PrimitiveType::UUID && is_uuid
            return Nodes::ConditionTreeLeaf.new(field, Operators::EQUAL, search_string)
          end

          nil
        end

        def get_fields(extended)
          fields = []
          @child_collection.schema[:fields].each do |name, field|
            fields.push([name, field]) if field.type == 'Column' && searchable_field?(field)

            if field.type == 'PolymorphicManyToOne' && extended
              ForestAdminAgent::Facades::Container.logger.log(
                'Debug',
                "We're not searching through #{self.name}.#{name} because it's a polymorphic relation. " \
                "You can override the default search behavior with 'replace_search'. " \
                'See more: https://docs.forestadmin.com/developer-guide-agents-ruby/agent-customization/search'
              )
            end

            to_one_relations = %w[ManyToOne OneToOne PolymorphicOneToOne]
            next unless extended && to_one_relations.include?(field.type)

            related = @child_collection.datasource.get_collection(field.foreign_collection)

            related.schema[:fields].each do |sub_name, sub_field|
              fields.push(["#{name}:#{sub_name}", sub_field]) if sub_field.type == 'Column' &&
                                                                 searchable_field?(sub_field)
            end
          end

          fields
        end

        def searchable_field?(field)
          operators = field.filter_operators

          if field.column_type == PrimitiveType::STRING
            return operators&.include?(Operators::EQUAL) ||
                   operators&.include?(Operators::CONTAINS) ||
                   operators&.include?(Operators::I_CONTAINS)
          end

          [PrimitiveType::UUID, PrimitiveType::ENUM, PrimitiveType::NUMBER].include?(field.column_type) &&
            operators&.include?(Operators::EQUAL)
        end

        def lenient_find(haystack, needle)
          haystack&.find { |v| v == needle.strip } || haystack&.find { |v| v.downcase == needle.downcase.strip }
        end

        def uuid?(value)
          value.to_s.downcase.match?(/^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i)
        end

        def number?(value)
          true if Float(value)
        rescue StandardError
          false
        end
      end
    end
  end
end
