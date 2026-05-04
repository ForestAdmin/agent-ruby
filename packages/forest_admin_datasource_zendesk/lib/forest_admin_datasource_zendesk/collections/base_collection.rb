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

      # Toolkit contract — subclasses override `aggregate_count` instead of
      # touching the 4-arg signature directly.
      def aggregate(caller, filter, aggregation, _limit = nil)
        unless aggregation.operation == 'Count' && aggregation.field.nil? && aggregation.groups.empty?
          raise ForestAdminDatasourceToolkit::Exceptions::ForestException,
                'Zendesk datasource only supports Count aggregation without groups.'
        end

        [{ 'value' => aggregate_count(caller, filter), 'group' => {} }]
      end

      protected

      # Default no-op; the Searchable mixin (and Ticket) override.
      def aggregate_count(_caller, _filter)
        raise NotImplementedError, "#{self.class} did not implement aggregate_count"
      end

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

        field, ascending = sort_field_and_direction(sort.first)
        zd_field = allow_list[field.to_s]
        return [nil, nil] unless zd_field

        [zd_field, ascending ? 'asc' : 'desc']
      end

      # Translates a Forest Page (offset/limit) into Zendesk's [page, per_page].
      def translate_page(page)
        return [1, Client::MAX_PER_PAGE] if page.nil?

        per_page = page.limit&.positive? ? [page.limit, Client::MAX_PER_PAGE].min : Client::MAX_PER_PAGE
        page_num = (page.offset.to_i / per_page) + 1
        [page_num, per_page]
      end

      def attrs_of(record)
        record.respond_to?(:attributes) ? record.attributes : record.to_h
      end

      # Resolves the records targeted by a write filter into their primary keys.
      # Mirrors the Mongoid datasource pattern: route through `list(... , ['id'])`
      # so any filter shape the read pipeline already understands works for
      # update/delete too (id-equality, id IN [...], or any condition the
      # Search API can express).
      def ids_for(caller, filter)
        list(caller, filter, ['id']).filter_map { |row| row['id'] }
      end

      def timezone_for(caller)
        return 'UTC' unless caller.respond_to?(:timezone)

        tz = caller.timezone
        tz.nil? || tz.empty? ? 'UTC' : tz
      end

      private

      # Sort entries arrive either as Sort::Clause objects (responding to
      # `field`/`ascending`) or as plain hashes (the toolkit normalises them
      # at construction time, but specs and a few code paths still build them
      # by hand). Handle both.
      #
      # `key?` (rather than `||`) for the boolean: `entry[:ascending] || ...`
      # would silently flip a descending sort to ascending if both symbol and
      # string keys exist with different values, and falls through to the
      # other key whenever ascending is explicitly false.
      def sort_field_and_direction(entry)
        return [entry.field, entry.ascending] if entry.respond_to?(:field)

        field     = entry.key?(:field)     ? entry[:field]     : entry['field']
        ascending = entry.key?(:ascending) ? entry[:ascending] : entry['ascending']
        [field, ascending]
      end
    end
  end
end
