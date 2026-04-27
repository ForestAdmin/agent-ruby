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

      protected

      # Pulls the value(s) from a leaf shaped like `id = N` or `id IN [...]`.
      # Used by collections to short-circuit PK lookups (Zendesk Search has no
      # `id:` operator, so /resource/{id} is the only viable path for show).
      def extract_id_lookup(node)
        return nil unless node.is_a?(Leaf) && node.field == 'id'

        case node.operator
        when Operators::EQUAL then [node.value]
        when Operators::IN    then Array(node.value)
        end
      end

      # Filters projection down to direct columns (drops "relation:subfield"
      # entries). Returns the record unchanged when projection is nil or
      # contains only relation paths.
      def project(record, projection)
        return record if projection.nil?

        wanted = Array(projection).map(&:to_s).reject { |p| p.include?(':') }
        return record if wanted.empty?

        wanted.each_with_object({}) { |k, h| h[k] = record[k] }
      end

      # Translates a Forest Sort into Zendesk's [sort_by, sort_order] tuple,
      # using the subclass-supplied allow-list. Unknown fields silently
      # disable sorting (Zendesk's Search API only honours specific fields).
      def translate_sort(sort, allow_list)
        return [nil, nil] if sort.nil? || sort.empty?

        first = sort.first
        field = first.respond_to?(:field) ? first.field : first[:field] || first['field']
        ascending = first.respond_to?(:ascending) ? first.ascending : (first[:ascending] || first['ascending'])
        zd_field = allow_list[field.to_s]
        return [nil, nil] unless zd_field

        [zd_field, ascending ? 'asc' : 'desc']
      end

      # Translates a Forest Page (offset/limit) into Zendesk's [page, per_page].
      def translate_page(page)
        return [1, Client::MAX_PER_PAGE] if page.nil?

        per_page = page.limit && page.limit.positive? ? [page.limit, Client::MAX_PER_PAGE].min : Client::MAX_PER_PAGE
        page_num = (page.offset.to_i / per_page) + 1
        [page_num, per_page]
      end

      def attrs_of(record)
        record.respond_to?(:attributes) ? record.attributes : record.to_h
      end

      def timezone_for(caller)
        return 'UTC' unless caller.respond_to?(:timezone)

        tz = caller.timezone
        tz.nil? || tz.empty? ? 'UTC' : tz
      end
    end
  end
end
