module ForestAdminDatasourceIntercom
  module Collections
    # What every Intercom collection shares: how a schema is declared, how a
    # record is narrowed to the projection asked for, and how a window is cut
    # out of records already in hand.
    #
    # Read-only for now: the writes and the business actions arrive with lot 3.
    # The relations towards Contacts and Companies wait for lot 4, those two
    # collections not existing yet -- a relation whose target collection is
    # missing is a schema the agent refuses to boot on. The relations between the
    # collections this datasource already serves are declared and answered here,
    # through `Relations`.
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

      protected

      def define_schema = raise(NotImplementedError, "#{self.class} did not implement define_schema")

      # A record narrowed to the columns that were asked for. A projection naming
      # a field the record does not carry yields nil rather than nothing at all:
      # the agent asked for a column, and an absent key would read as a record
      # missing it.
      #
      # A path through a relation is not a column and is skipped here: it is
      # answered by `embed_relations`, which nests a whole row under the relation
      # name once the page is in hand.
      #
      # No projection at all asks for every column -- which is not the same as
      # every key a serialized record happens to carry: a couple of them hold
      # what a column is read *from*, the ids behind a membership for one, and
      # publishing those would show the operator the plumbing.
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
        limit = page.limit.to_i
        return records.drop(offset) unless limit.positive?

        records[offset, limit] || []
      end

      def column_names
        @column_names ||= fields.select { |_, field| field.is_a?(ColumnSchema) }.keys
      end

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
    end
  end
end
