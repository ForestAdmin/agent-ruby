module ForestAdminDatasourceCustomizer
  module Decorators
    module Search
      class SearchCollectionDecorator < ForestAdminDatasourceToolkit::Decorators::CollectionDecorator
        include ForestAdminDatasourceToolkit::Schema
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
        include ForestAdminDatasourceToolkit::Exceptions

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

        def replace_search(replacer)
          assert_selection_resolves(replacer)
          @replacer = replacer
          @disabled_search = false
          warn_extended_search_refused if handler
          mark_schema_as_dirty
        end

        def refine_schema(sub_schema)
          sub_schema.merge({ searchable: !@disabled_search })
        end

        def refine_filter(caller, filter)
          # Search string is not significant
          return filter.override({ search: nil }) if !filter || !filter.search || filter.search.strip&.empty?

          # Let sub-collection deal with the search
          return filter unless implements_search?

          tree = if handler
                   ctx = ForestAdminDatasourceCustomizer::Context::CollectionCustomizationContext.new(self, caller)
                   ConditionTreeFactory.from_plain_object(handler.call(filter.search, filter.search_extended, ctx))
                 else
                   search_condition_tree(filter.search, filter.search_extended)
                 end

          filter.override({
                            condition_tree: ConditionTreeFactory.intersect([filter.condition_tree, tree]),
                            search: nil
                          })
        end

        # Answers against +@child_collection+, which is what the search actually reads: a field
        # hidden by the publication or renaming layers above is still searched.
        #
        # The term is run through the same +build_condition+ selection +refine_filter+ applies, so a
        # field the search cannot match — a number column for a word, a uuid column for anything
        # else — is left out rather than reported as reached.
        #
        # +nil+ whenever this layer does not choose the fields — a callable replacer is installed, or
        # the child collection searches natively — because then no enumeration made here is true.
        def searched_fields(search, extended)
          return nil unless enumerable_search?
          return [] if insignificant_search?(search)

          searchable_fields(extended).filter_map do |path, schema|
            searched_field(path) if build_condition(path, schema, search)
          end
        end

        def search_handler?
          !handler.nil?
        end

        private

        # Warned at boot, not left to the first caller who trips the 403: blocks installed before this
        # version were served. Nil-guarded because the RPC agent runs its own +AgentFactory+ subclass,
        # so the base facade's container is never built there — a customization must not become a boot
        # failure over a warning.
        def warn_extended_search_refused
          logger = ForestAdminAgent::Facades::Container.logger

          return if logger.nil?

          logger.log(
            'Warn',
            "An extended search on #{name} is refused where permissions are enabled: a " \
            '`replace_search` block names no field, so the agent cannot check what it reads against ' \
            "the caller's permissions. Declaring the search with " \
            '`replace_search(include_fields: [...])` makes it checkable.'
          )
        end

        def handler
          @replacer.respond_to?(:call) ? @replacer : nil
        end

        def field_selection
          @replacer.respond_to?(:call) ? nil : @replacer
        end

        def implements_search?
          !@replacer.nil? || !@child_collection.schema[:searchable]
        end

        def enumerable_search?
          handler.nil? && implements_search?
        end

        def assert_selection_resolves(replacer)
          return if replacer.nil? || replacer.respond_to?(:call)

          selected = field_paths(replacer[:only_fields]) + field_paths(replacer[:include_fields])
          excluded = field_paths(replacer[:exclude_fields])

          selected.each { |path| selected_field(path) }
          excluded.each { |path| excluded_field(path) }

          overlap = selected.select { |path| excluded?(path, excluded) }

          return if overlap.empty?

          raise ForestException,
                "Cannot both search and exclude #{overlap.map { |path| "'#{path}'" }.join(", ")}"
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
          conditions = searchable_fields(extended).filter_map do |field, schema|
            build_condition(field, schema, search)
          end

          return ConditionTreeFactory.match_none if conditions.empty?

          ConditionTreeFactory.union(conditions)
        end

        # Both the condition tree +refine_filter+ builds and the footprint +searched_fields+ reports
        # come from here: a path the search reads without appearing in the footprint is a column read
        # unchecked.
        def searchable_fields(extended)
          selection = field_selection || {}
          only_fields = selection[:only_fields]

          defaults = only_fields ? {} : get_fields(extended).to_h
          selected = field_paths(only_fields) + field_paths(selection[:include_fields])

          excluded = field_paths(selection[:exclude_fields])

          defaults
            .merge(selected.to_h { |path| resolved_field(path) })
            .reject { |path, _schema| excluded?(path, excluded) }
        end

        def excluded?(path, excluded)
          excluded.any? { |name| path == name || path.start_with?("#{name}:") }
        end

        # Unlike a selected path, a bare to-one relation is legal here: it drops every path through it,
        # where naming the target's columns would have to be revisited each time it gains one. What is
        # refused is a name the search never reads either way — a to-many, a depth-2 path, a column no
        # term can match — because excluding it silently changes nothing.
        def excluded_field(path)
          schema = ForestAdminDatasourceToolkit::Utils::Collection.get_field_schema(@child_collection, path)

          return schema if excludable?(path, schema)

          raise ForestException, "Cannot exclude '#{path}' from the search: the search does not read it"
        end

        def excludable?(path, schema)
          return path.count(':') <= 1 && searchable_field?(schema) if schema.type == 'Column'

          !path.include?(':') && TO_ONE_RELATIONS.include?(schema.type)
        end

        def field_paths(names)
          Array(names).map(&:to_s)
        end

        # Strict where an end-user term would be interpreted: this list is written by the developer,
        # so a name that names nothing, or names a relation the search cannot compare a term to, is a
        # mistake to report.
        def resolved_field(path)
          schema = ForestAdminDatasourceToolkit::Utils::Collection.get_field_schema(@child_collection, path)

          unless schema.type == 'Column'
            raise ForestException, "Cannot search on '#{path}': a #{schema.type} is not a column"
          end

          [path, schema]
        end

        # A Number, Enum or UUID column reaching `build_condition` gets an EQUAL leaf its datasource
        # never declared, and `get_fields` skips it silently — so a named one is refused instead.
        def selected_field(path)
          resolved = resolved_field(path)
          schema = resolved.last

          unless searchable_field?(schema)
            raise ForestException,
                  "Cannot search on '#{path}': its #{schema.column_type} column declares no filter " \
                  'operator a search term can use'
          end

          resolved
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
