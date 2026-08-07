module ForestAdminDatasourcePylon
  module Collections
    class BaseCollection < ForestAdminDatasourceToolkit::Collection
      ColumnSchema = ForestAdminDatasourceToolkit::Schema::ColumnSchema
      Operators    = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators
      Leaf         = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

      STRING_OPS = [Operators::EQUAL, Operators::NOT_EQUAL, Operators::IN, Operators::NOT_IN,
                    Operators::PRESENT, Operators::BLANK].freeze
      NUMBER_OPS = (STRING_OPS + [Operators::GREATER_THAN, Operators::LESS_THAN]).freeze
      DATE_OPS   = [Operators::EQUAL, Operators::BEFORE, Operators::AFTER,
                    Operators::PRESENT, Operators::BLANK].freeze

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
      def extract_id_lookup(node)
        return nil unless node.is_a?(Leaf) && node.field == 'id'

        return unless [Operators::EQUAL, Operators::IN].include?(node.operator)

        Array(node.value).map(&:to_s).reject(&:empty?)
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
    end
  end
end
