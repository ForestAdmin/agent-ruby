module ForestAdminDatasourceZendesk
  module Collections
    class BaseCollection < ForestAdminDatasourceToolkit::Collection
      ColumnSchema = ForestAdminDatasourceToolkit::Schema::ColumnSchema
      Operators    = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators
      Leaf         = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

      STRING_OPS  = [Operators::EQUAL, Operators::NOT_EQUAL, Operators::IN, Operators::NOT_IN,
                     Operators::PRESENT, Operators::BLANK].freeze
      NUMBER_OPS  = (STRING_OPS + [Operators::GREATER_THAN, Operators::LESS_THAN]).freeze
      DATE_OPS    = [Operators::EQUAL, Operators::BEFORE, Operators::AFTER,
                     Operators::PRESENT, Operators::BLANK].freeze

      def aggregate(caller, filter, aggregation, _limit = nil)
        unless aggregation.operation == 'Count' && aggregation.field.nil? && aggregation.groups.empty?
          raise ForestAdminDatasourceToolkit::Exceptions::ForestException,
                'Zendesk datasource only supports Count aggregation without groups.'
        end

        [{ 'value' => aggregate_count(caller, filter), 'group' => {} }]
      end

      protected

      def aggregate_count(_caller, _filter)
        raise NotImplementedError, "#{self.class} did not implement aggregate_count"
      end

      # Zendesk Search has no `id:` operator, so collections short-circuit
      # PK lookups to /resource/{id} when the filter is `id = N` or `id IN [...]`.
      def extract_id_lookup(node)
        return nil unless node.is_a?(Leaf) && node.field == 'id'

        case node.operator
        when Operators::EQUAL then [node.value]
        when Operators::IN    then Array(node.value)
        end
      end

      def project(record, projection)
        return record if projection.nil?

        wanted = Array(projection).map(&:to_s).reject { |p| p.include?(':') }
        return record if wanted.empty?

        wanted.to_h { |k| [k, record[k]] }
      end

      # Unknown fields silently disable sorting — Zendesk's Search API only
      # honours a fixed allow-list per resource.
      def translate_sort(sort, allow_list)
        return [nil, nil] if sort.nil? || sort.empty?

        field, ascending = sort_field_and_direction(sort.first)
        zd_field = allow_list[field.to_s]
        return [nil, nil] unless zd_field

        [zd_field, ascending ? 'asc' : 'desc']
      end

      def translate_page(page)
        return [1, Client::MAX_PER_PAGE] if page.nil?

        per_page = page.limit&.positive? ? [page.limit, Client::MAX_PER_PAGE].min : Client::MAX_PER_PAGE
        page_num = (page.offset.to_i / per_page) + 1
        [page_num, per_page]
      end

      def attrs_of(record)
        record.respond_to?(:attributes) ? record.attributes : record.to_h
      end

      def ids_for(caller, filter)
        list(caller, filter, ['id']).filter_map { |row| row['id'] }
      end

      def timezone_for(caller)
        return 'UTC' unless caller.respond_to?(:timezone)

        tz = caller.timezone
        tz.nil? || tz.empty? ? 'UTC' : tz
      end

      def build_zendesk_query(caller, filter)
        translated = ForestAdminDatasourceZendesk::Query::ConditionTreeTranslator.call(
          filter.condition_tree, timezone: timezone_for(caller),
                                 custom_fields: datasource.custom_field_mapping
        )
        [translated, filter.search].compact.reject(&:empty?).join(' ')
      end

      private

      def sort_field_and_direction(entry)
        return [entry.field, entry.ascending] if entry.respond_to?(:field)

        field     = entry.key?(:field)     ? entry[:field]     : entry['field']
        ascending = entry.key?(:ascending) ? entry[:ascending] : entry['ascending']
        [field, ascending]
      end
    end
  end
end
