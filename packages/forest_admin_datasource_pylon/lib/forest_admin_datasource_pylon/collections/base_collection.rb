module ForestAdminDatasourcePylon
  module Collections
    class BaseCollection < ForestAdminDatasourceToolkit::Collection
      ColumnSchema         = ForestAdminDatasourceToolkit::Schema::ColumnSchema
      Operators            = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators
      Branch               = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeBranch
      Leaf                 = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf
      ConditionTreeFactory = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::ConditionTreeFactory

      # `residual` holds the conditions left over once the primary-key leaf has
      # been taken out of the tree, for the caller to apply in memory.
      IdLookup = Struct.new(:ids, :residual, keyword_init: true)

      attr_reader :custom_fields

      # Template method: subclasses implement `define_schema` and
      # `define_relations` as hooks; ordering between them, custom-field
      # registration, and the search/count flags is owned here so collisions
      # are always evaluated against the final native schema.
      def initialize(datasource, name, custom_fields: [], searchable: false, countable: false, native_driver: nil)
        super(datasource, name, native_driver)
        define_schema
        define_relations
        @custom_fields = add_custom_fields(custom_fields)
        enable_search if searchable
        enable_count if countable
      end

      protected

      # Pylon has no `id` filter operator on /issues/search, so collections
      # short-circuit primary-key lookups to /resource/{id}. Ids are UUID
      # strings — unlike Zendesk, nothing has to be coerced to an integer.
      #
      # The leaf is also pulled out of a top-level AND, because Forest sends
      # `AND(id equal X, <scope>)` on a record detail as soon as a scope or a
      # segment is set, and `id` is not a field Pylon can filter on.
      def extract_id_lookup(node)
        ids = id_values(node)
        return IdLookup.new(ids: ids, residual: nil) if ids
        return nil unless and_branch?(node)

        conditions = Array(node.conditions)
        id_index = conditions.index { |condition| id_values(condition) }
        return nil if id_index.nil?

        residual = conditions.reject.with_index { |_, index| index == id_index }
        IdLookup.new(ids: id_values(conditions[id_index]), residual: ConditionTreeFactory.intersect(residual))
      end

      def build_pylon_filter(caller, filter)
        Query::ConditionTreeTranslator.call(filter&.condition_tree,
                                            api_filters: api_filters,
                                            timezone: timezone_for(caller))
      end

      # Overridden by collections whose endpoint can filter server-side.
      def api_filters
        {}
      end

      # An unknown field silently disables sorting: a Pylon endpoint only honours
      # the fixed allow-list its collection declares.
      def translate_sort(sort, allow_list)
        return [nil, nil] if sort.nil? || sort.empty?

        field, ascending = sort_field_and_direction(sort.first)
        pylon_field = allow_list[field.to_s]
        return [nil, nil] unless pylon_field

        [pylon_field, ascending ? 'asc' : 'desc']
      end

      def timezone_for(caller)
        return 'UTC' unless caller.respond_to?(:timezone)

        timezone = caller.timezone
        timezone.nil? || timezone.to_s.empty? ? 'UTC' : timezone
      end

      def project(record, projection)
        return record if projection.nil?

        wanted = Array(projection).map(&:to_s).reject { |p| p.include?(':') }
        return record if wanted.empty?

        wanted.to_h { |k| [k, record[k]] }
      end

      def translate_page(page)
        return [0, Client::MAX_SEARCH_LIMIT] if page.nil?

        limit = page.limit.to_i.positive? ? page.limit.to_i : Client::MAX_SEARCH_LIMIT
        [page.offset.to_i.clamp(0, nil), limit]
      end

      # Adds custom fields, skipping any whose column name collides with a
      # field already declared on the collection. Returns the subset actually
      # added so callers can keep their serializer in sync with the schema.
      def add_custom_fields(custom_fields)
        custom_fields.reject do |cf|
          column_name = cf[:column_name]
          if schema[:fields].key?(column_name)
            ForestAdminDatasourcePylon.logger.warn(
              "[forest_admin_datasource_pylon] Custom field '#{column_name}' on collection " \
              "'#{name}' conflicts with an existing field; skipping."
            )
            true
          else
            add_field(column_name, cf[:schema])
            false
          end
        end
      end

      private

      def define_schema    = raise(NotImplementedError, "#{self.class} did not implement define_schema")
      def define_relations = raise(NotImplementedError, "#{self.class} did not implement define_relations")

      def id_values(node)
        return nil unless node.is_a?(Leaf) && node.field == 'id'
        return nil unless [Operators::EQUAL, Operators::IN].include?(node.operator)

        Array(node.value).map(&:to_s).reject(&:empty?)
      end

      def and_branch?(node)
        node.is_a?(Branch) && node.aggregator.to_s.casecmp('and').zero?
      end

      def sort_field_and_direction(entry)
        return [entry.field, entry.ascending] if entry.respond_to?(:field)

        field     = entry.key?(:field)     ? entry[:field]     : entry['field']
        ascending = entry.key?(:ascending) ? entry[:ascending] : entry['ascending']
        [field, ascending]
      end
    end
  end
end
