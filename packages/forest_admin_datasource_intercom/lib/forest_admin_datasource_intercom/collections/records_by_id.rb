module ForestAdminDatasourceIntercom
  module Collections
    # `id equals X` / `id in [...]` answered by the record endpoint, plus exact counting -- shared
    # by the two paginated tiers, where a count over collected pages would answer a fraction.
    module RecordsById
      Operators = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators
      Leaf = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf
      Aggregation = ForestAdminDatasourceToolkit::Components::Query::Aggregation

      # How many records a bulk read by id may fetch. Intercom exposes no "read
      # these records" endpoint, so a set of ids is one request each -- the
      # fan-out is bounded rather than turned into a rate limit halfway through
      # a page. The collection that reads its ids in bulk raises the figure.
      MAX_ID_READS = 25

      protected

      # The endpoint one record is read from.
      def record_endpoint = raise(NotImplementedError, "#{self.class} did not implement record_endpoint")

      # What rides along on that read. `display_as=plaintext` for the tiers
      # whose records carry bodies written by end customers; nothing elsewhere.
      def record_read_params = {}

      def max_id_reads = MAX_ID_READS

      # A bare primary-key leaf only: answering an `and` carrying a scope, or a search, with the
      # ids alone would serve records it excludes. Deduplicated so an id is not read twice.
      def id_lookup(filter)
        tree = filter&.condition_tree
        return nil unless tree.is_a?(Leaf) && tree.field.to_s == primary_key
        return nil unless blank_search?(filter)

        case tree.operator
        when Operators::EQUAL then [tree.value].compact.map(&:to_s).uniq
        when Operators::IN then Array(tree.value).compact.map(&:to_s).uniq
        end
      end

      # A record the operator can no longer reach -- deleted, or outside the
      # token's scope -- reads as "no record" rather than as a failed page.
      def records_by_ids(ids)
        wanted = ids.first(max_id_reads)
        warn_truncated_ids(ids.size) if ids.size > wanted.size

        client.fetch_records(record_endpoint, wanted, params: record_read_params).compact
      end

      # How many of a set of ids name a record, which means reading them:
      # Intercom has no "how many of these exist" endpoint. Past what a bulk
      # read may fetch the count is refused rather than answered with the number
      # the truncation left -- both paginated tiers advertise an exact count,
      # and "25" where the question named forty records is not one.
      def count_by_ids(ids)
        refuse_id_count!(ids.size) if ids.size > max_id_reads

        records_by_ids(ids).size
      end

      # The count Intercom answered, or nothing at all. Counting the pages a
      # read collected would answer a fraction of the collection as if it were
      # the whole of it, which is the one thing the paginated tiers do not do.
      def exact_count(page)
        return page.total_count if page.total_count

        raise UnsupportedOperatorError,
              "#{name} cannot be counted: Intercom answered this listing without a total_count, and counting the " \
              'pages the agent read would answer a fraction of the collection as if it were the whole of it.'
      end

      def refuse_unsupported_aggregation!(aggregation)
        return if aggregation.is_a?(Aggregation) && aggregation.operation.to_s.casecmp('count').zero? &&
                  Array(aggregation.groups).empty? && aggregation.field.nil?

        raise UnsupportedOperatorError,
              "#{name} can only be counted: Intercom exposes no aggregate endpoint, and grouping or summing the " \
              'pages the agent read would answer a fraction of the collection as if it were the whole of it. ' \
              'Chart it on a collection read whole, or wait for the bounded group-by of the reporting lot.'
      end

      def refuse_id_count!(asked)
        raise UnsupportedOperatorError,
              "#{name} cannot count #{asked} records by id: Intercom exposes no endpoint that counts a set of ids, " \
              "so counting them means reading them, and this reads #{max_id_reads} at most. Counting the ones it " \
              'read would answer a number smaller than the question. Narrow the condition, or count the ' \
              'collection with a filter it answers instead of a list of ids.'
      end

      def warn_truncated_ids(asked)
        ForestAdminDatasourceIntercom.logger.warn(
          "[forest_admin_datasource_intercom] #{name} was asked for #{asked} records by id and read the first " \
          "#{max_id_reads}: Intercom reads them one request each. The result is truncated."
        )
      end

      def blank_search?(filter)
        search = filter.respond_to?(:search) ? filter.search : nil

        search.nil? || search.to_s.strip.empty?
      end
    end
  end
end
