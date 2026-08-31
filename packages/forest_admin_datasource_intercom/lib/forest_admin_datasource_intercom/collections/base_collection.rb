module ForestAdminDatasourceIntercom
  module Collections
    # What every Intercom collection shares: how a schema is declared, how a
    # record is narrowed to the projection asked for, and how a window is cut
    # out of records already in hand.
    #
    # Read-only for now. The writes and the business actions arrive with lot 3,
    # and the relations with lot 4, once Contacts and Companies exist -- a
    # relation whose target collection is missing is a schema the agent refuses
    # to boot on.
    class BaseCollection < ForestAdminDatasourceToolkit::Collection
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

      # A record narrowed to what was asked for. A projection naming a field the
      # record does not carry yields nil rather than nothing at all: the agent
      # asked for a column, and an absent key would read as a record missing it.
      def project(record, projection)
        fields = Array(projection)
        return record if fields.empty?

        fields.to_h { |field| [field, record[field]] }
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
