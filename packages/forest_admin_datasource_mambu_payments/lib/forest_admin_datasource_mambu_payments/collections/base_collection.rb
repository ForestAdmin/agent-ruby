module ForestAdminDatasourceMambuPayments
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
      BOOL_OPS   = [Operators::EQUAL, Operators::NOT_EQUAL,
                    Operators::PRESENT, Operators::BLANK].freeze

      def aggregate(caller, filter, aggregation, _limit = nil)
        unless aggregation.operation == 'Count' && aggregation.field.nil? && aggregation.groups.empty?
          raise ForestAdminDatasourceToolkit::Exceptions::ForestException,
                'Mambu Payments datasource only supports Count aggregation without groups.'
        end

        [{ 'value' => aggregate_count(caller, filter), 'group' => {} }]
      end

      protected

      def aggregate_count(_caller, _filter)
        raise NotImplementedError, "#{self.class} did not implement aggregate_count"
      end

      def extract_id_lookup(node)
        return nil unless node.is_a?(Leaf) && node.field == 'id'

        case node.operator
        when Operators::EQUAL then [node.value]
        when Operators::IN    then Array(node.value)
        end
      end

      # Server-filterable fields the Numeral API accepts for this collection.
      # Subclasses override with entries like:
      #   { 'connected_account_id' => { ops: [Operators::EQUAL, Operators::IN] } }
      # Anything not declared here raises UnsupportedOperatorError when filtered
      # on, so we never silently return unfiltered results.
      def api_filters
        {}
      end

      def translate_filters(condition_tree)
        Query::ConditionTreeTranslator.call(condition_tree, api_filters: api_filters)
      end

      def project(record, projection)
        return record if projection.nil?

        wanted = Array(projection).map(&:to_s).reject { |p| p.include?(':') }
        return record if wanted.empty?

        wanted.to_h { |k| [k, record[k]] }
      end

      def translate_page(page)
        return [1, Client::MAX_PER_PAGE] if page.nil?

        per_page = page.limit&.positive? ? [page.limit, Client::MAX_PER_PAGE].min : Client::MAX_PER_PAGE
        page_num = (page.offset.to_i / per_page) + 1
        [page_num, per_page]
      end

      def ids_for(caller, filter)
        list(caller, filter, ['id']).filter_map { |row| row['id'] }
      end

      def attrs_of(record)
        record.respond_to?(:attributes) ? record.attributes : record.to_h
      end

      # Returns the relation prefixes (everything before `:`) requested in the
      # projection - e.g. ["connected_account"] for ["id", "connected_account:name"].
      def relations_in(projection)
        Array(projection).map(&:to_s).filter_map { |p| p.split(':').first if p.include?(':') }.uniq
      end

      # Bulk-fetches records for a ManyToOne relation and writes the serialized
      # related record back onto each row. The customizer's relation decorator
      # only handles emulated relations, so native datasource relations (like
      # ours) must populate the sub-record themselves.
      #
      # Expected opts keys: :foreign_key, :relation_name, :fetcher, :serializer.
      def embed_many_to_one(rows, sources, projection, **opts)
        relation_name = opts.fetch(:relation_name)
        return if projection.nil? || !relations_in(projection).include?(relation_name)

        foreign_key = opts.fetch(:foreign_key)
        ids = sources.filter_map { |s| s[foreign_key] }.reject { |id| id.nil? || id.to_s.empty? }.uniq
        return if ids.empty?

        cache = ids.to_h { |id| [id, opts.fetch(:fetcher).call(id)] }.compact
        rows.each_with_index do |row, i|
          fk_value = sources[i][foreign_key]
          next if fk_value.nil? || fk_value.to_s.empty?

          raw = cache[fk_value]
          row[relation_name] = raw && opts.fetch(:serializer).call(raw)
        end
      end
    end
  end
end
