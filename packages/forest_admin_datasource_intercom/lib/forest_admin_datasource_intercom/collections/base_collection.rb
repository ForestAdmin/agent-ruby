module ForestAdminDatasourceIntercom
  module Collections
    # Read-only for now: writes and business actions arrive with lot 3. A relation to
    # a collection not served yet is a schema the agent refuses to boot on.
    class BaseCollection < ForestAdminDatasourceToolkit::Collection
      include Relations

      ColumnSchema = ForestAdminDatasourceToolkit::Schema::ColumnSchema
      Operators = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators
      Equivalent = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::ConditionTreeEquivalent
      Leaf = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

      def initialize(datasource, name)
        super
        define_schema
      end

      def client
        datasource.client
      end

      # How many ids this collection resolves per `list`, and in total, as a relation target.
      # Nil means unbounded: the tier read whole answers any number of ids in one request.
      def ids_per_read = nil
      def max_resolvable_ids = nil

      protected

      def define_schema = raise(NotImplementedError, "#{self.class} did not implement define_schema")

      # A missing field yields nil rather than an absent key; relation paths are left to
      # `embed_relations`. No projection means every column, not every serialized key:
      # some keys are internal plumbing (e.g. the ids behind a membership).
      def project(record, projection)
        asked = Array(projection).map(&:to_s)
        return record.slice(*column_names) if asked.empty?

        asked.reject { |field| field.include?(':') }.to_h { |field| [field, record[field]] }
      end

      # Whether a projection asks for a column. No projection at all asks for
      # every declared column, which is how `project` reads it -- an enrichment
      # guarded on the column being named would leave nil the very column the
      # projection publishes.
      def column_asked?(projection, column)
        asked = Array(projection).map(&:to_s)

        asked.empty? || asked.include?(column)
      end

      # Whether a projection asks for any of a group of columns, read the same
      # way: no projection at all asks for every one of them.
      def any_column_asked?(projection, columns)
        asked = Array(projection).map(&:to_s)

        asked.empty? || columns.any? { |column| asked.include?(column) }
      end

      # The window a list view asked for, cut out of records already in hand.
      #
      # A filter with no page -- or a page naming no limit -- asks for every
      # record it matched, and there is nothing to cut. How far the read that
      # collected them went is a different question, answered by the walker and
      # its caps.
      def page_window(records, filter)
        page = filter&.page
        return records if page.nil?

        offset = page.offset.to_i.clamp(0, nil)
        limit = page_limit(page)
        return records.drop(offset) if limit.nil?

        records[offset, limit] || []
      end

      # Nil when the page names no limit, and an explicit zero kept as one: the
      # toolkit's `Page#apply` reads it as an empty window, never as "all".
      def page_limit(page)
        page.limit&.to_i&.clamp(0, nil)
      end

      def column_names
        @column_names ||= fields.select { |_, field| field.is_a?(ColumnSchema) }.keys
      end

      # The columns a workspace's own attributes became. None here; the
      # collections that carry any override this through `CustomAttributes`.
      # The translator reads them to answer a filter on one with the refusal
      # covering the family rather than with the message for a column nobody
      # declared.
      def attribute_column_names = []

      # The timezone in-memory date comparisons are evaluated in. The caller's,
      # since that is whose "today" the filter was written against.
      def timezone_for(caller)
        caller.respond_to?(:timezone) ? caller.timezone : nil
      end

      # Ids reach this datasource as strings -- a filter value from Forest, a
      # segment, a url -- while Intercom types them inconsistently: a team id is
      # a string, the same team's id inside `admin_ids` is a number. Left as it
      # comes, an integer id would never match the string the filter carries.
      def stringify_id(value)
        value&.to_s
      end

      # Intercom nests its lists twice -- `{"type": "contact.list", "contacts":
      # [...]}` -- and answers a null instead of an empty list when there is
      # nothing.
      def nested_list(container, key)
        return [] unless container.is_a?(Hash)

        list = container[key]
        list.is_a?(Array) ? list : []
      end

      # Intercom dates travel as epoch seconds; Forest reads a Date column as an
      # ISO8601 string, and a filter carries one too, so comparing the two is the
      # ordering itself. UTC deliberately: that is where Intercom stores and
      # truncates, and rendering a local time here would hide the very shift that
      # makes a day-granular date filter wrong.
      def stamp(seconds)
        return nil unless seconds.is_a?(Numeric) && seconds.positive?

        Time.at(seconds).utc.iso8601
      end

      # --- Reading a sort clause -------------------------------------------
      #
      # Forest hands a clause keyed with symbols or with strings depending on
      # where it was written, and all three tiers have to read one.

      def primary_key
        @primary_key ||= fields.find do |_name, field|
          field.respond_to?(:is_primary_key) && field.is_primary_key
        end&.first
      end

      def sort_field(clause) = clause[:field] || clause['field']

      # `key?` rather than `||`: a descending clause carries `false`, which an
      # `||` fallback reads as "absent" -- so an explicit `?sort=-id` would be
      # taken for the ascending default the agent injects.
      def ascending?(clause)
        clause.key?(:ascending) ? clause[:ascending] : clause['ascending']
      end

      # The ascending primary-key sort the agent injects when a request names
      # none. Not an order anybody asked for, so a tier that cannot honour one
      # stays quiet about this one.
      def default_pk_sort?(clauses)
        return false unless clauses.size == 1

        clause = clauses.first
        return false unless sort_field(clause).to_s == primary_key

        ascending?(clause) != false
      end
    end
  end
end
