module ForestAdminDatasourceCustomizer
  module Decorators
    module Search
      class SearchCollectionDecorator < ForestAdminDatasourceToolkit::Decorators::CollectionDecorator
        include ForestAdminDatasourceToolkit::Schema
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

        POLYMORPHIC_TYPES = %w[PolymorphicManyToOne PolymorphicOneToOne].freeze
        TO_ONE_RELATIONS = %w[ManyToOne OneToOne].freeze

        def initialize(child_collection, datasource)
          super
          @replacer = nil
          @disabled_search = get_fields(false).empty?
        end

        def disable_search
          @disabled_search = true
          mark_schema_as_dirty
        end

        # +replacer+ is either a callable, which picks its own fields, or a field selection naming
        # the fields the default search reads.
        def replace_search(replacer)
          @replacer = replacer
          assert_selection_resolves
          @disabled_search = false
          mark_schema_as_dirty
        end

        def refine_schema(sub_schema)
          sub_schema.merge({ searchable: !@disabled_search })
        end

        def refine_filter(caller, filter)
          # Search string is not significant
          return filter.override({ search: nil }) if !filter || !filter.search || filter.search.strip&.empty?

          # Implement search ourselves
          if @replacer || !@child_collection.schema[:searchable]
            tree = if handler
                     ctx = ForestAdminDatasourceCustomizer::Context::CollectionCustomizationContext.new(self, caller)
                     ConditionTreeFactory.from_plain_object(
                       handler.call(filter.search, filter.search_extended, ctx)
                     )
                   else
                     search_condition_tree(filter.search, filter.search_extended)
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

        # Answers against +@child_collection+, which is what the search actually reads: a field
        # hidden by the publication or renaming layers above is still searched.
        #
        # The term is run through the same +build_condition+ selection +refine_filter+ applies, so a
        # field the search cannot match — a number column for a word, a uuid column for anything
        # else — is left out rather than reported as reached.
        #
        # +nil+ whenever this layer does not choose the fields — a callable replacer is installed, or
        # the child collection searches natively — because then no enumeration made here is true. A
        # field selection is a declarative list, so it is answered rather than refused.
        def searched_fields(search, extended)
          return nil unless enumerable_search?
          return [] if insignificant_search?(search)

          searchable_fields(extended).filter_map do |path, schema|
            searched_field(path) if build_condition(path, schema, search)
          end
        end

        private

        def handler
          @replacer.respond_to?(:call) ? @replacer : nil
        end

        def field_selection
          @replacer.respond_to?(:call) ? nil : @replacer
        end

        # The footprint is knowable exactly when this layer builds the condition tree, which is the
        # condition +refine_filter+ tests: a replacer is installed, or the child cannot search. Only
        # a callable then picks fields no enumeration made here can name.
        def enumerable_search?
          handler.nil? && (!@replacer.nil? || !@child_collection.schema[:searchable])
        end

        # Resolved when the customization is applied rather than per request: a name that resolves
        # to nothing would otherwise drop out of the searchable set unnoticed and leave the search
        # matching nothing for good.
        def assert_selection_resolves
          selection = field_selection

          return if selection.nil?

          selected_paths(selection).each { |path| resolved_field(path) }
        end

        def insignificant_search?(search)
          search.nil? || search.strip.empty?
        end

        def searched_field(path)
          {
            path: path,
            collections: ForestAdminDatasourceToolkit::Utils::FieldPath.leaf_collection_names(
              @child_collection, path
            )
          }
        end

        def search_condition_tree(search, extended)
          conditions = searchable_fields(extended).map do |field, schema|
            build_condition(field, schema, search)
          end

          ConditionTreeFactory.union(conditions)
        end

        # Both the condition tree +refine_filter+ builds and the footprint +searched_fields+ reports
        # come from here: a path the search reads without appearing in the footprint is a column read
        # unchecked.
        #
        # Keyed by path, so a field named twice — a selected one that is already a default — is
        # searched and reported once. Defaults are merged first, which is what decides the order the
        # footprint is reported in.
        def searchable_fields(extended)
          selection = field_selection || {}
          only_fields = selection[:only_fields]

          defaults = only_fields ? {} : get_fields(extended).to_h
          selected = (Array(only_fields) + Array(selection[:include_fields])).map { |path| resolved_field(path) }

          defaults.merge(selected.to_h).except(*Array(selection[:exclude_fields]))
        end

        def selected_paths(selection)
          Array(selection[:only_fields]) +
            Array(selection[:include_fields]) +
            Array(selection[:exclude_fields])
        end

        # Strict on purpose: this list is written by the developer, so a name that names nothing is a
        # mistake to report, not a term to interpret. +get_field_schema+ names the field it could not
        # resolve, and refuses a path crossing anything but a to-one relation — a polymorphic one
        # included, which the search does not follow either.
        def resolved_field(path)
          [path, ForestAdminDatasourceToolkit::Utils::Collection.get_field_schema(@child_collection, path)]
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

            if POLYMORPHIC_TYPES.include?(field.type) && extended
              ForestAdminAgent::Facades::Container.logger.log(
                'Debug',
                "We're not searching through #{self.name}.#{name} because it's a polymorphic relation. " \
                "You can override the default search behavior with 'replace_search'. " \
                'See more: https://docs.forestadmin.com/developer-guide-agents-ruby/agent-customization/search'
              )
            end

            next unless extended && TO_ONE_RELATIONS.include?(field.type)

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
