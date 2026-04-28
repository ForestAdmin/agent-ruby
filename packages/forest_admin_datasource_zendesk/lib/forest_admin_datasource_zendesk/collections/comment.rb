module ForestAdminDatasourceZendesk
  module Collections
    # Comments are *always* fetched in the context of a parent ticket
    # (Zendesk: GET /tickets/{id}/comments). The collection's `list` only
    # responds to filters that resolve to one or more `ticket_id` values
    # (either directly via `ticket_id = N` / `ticket_id IN [...]`, or
    # indirectly via the synthetic primary key `<comment_id>-<ticket_id>`).
    # Any other filter shape returns [].
    class Comment < BaseCollection
      ManyToOneSchema = ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema
      Branch          = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeBranch

      def initialize(datasource)
        super(datasource, 'ZendeskComment')
        define_schema
        define_relations
      end

      def list(_caller, filter, projection)
        ticket_ids, comment_ids = resolve_scope(filter)
        if ticket_ids.empty?
          ForestAdminDatasourceZendesk.logger.info(
            '[forest_admin_datasource_zendesk] ZendeskComment.list called without a ticket scope; ' \
            'returning [] (use the Ticket -> comments relation to fetch comments)'
          )
          return []
        end

        records = fetch_comments(ticket_ids, comment_ids)
        records.map { |c| project(serialize(c), projection) }
      end

      private

      # Resolves the filter into [ticket_ids, comment_ids]. Both come from a
      # mix of direct `ticket_id` filters and synthetic-id filters
      # (`id = "<comment_id>-<ticket_id>"`). `comment_ids` may be nil
      # (meaning "no narrowing — return all comments for the ticket").
      def resolve_scope(filter)
        decoded = decoded_synthetic_pairs(filter)
        ticket_ids = ((extract_field_lookup(filter.condition_tree, 'ticket_id') || []) +
                      decoded.map(&:last)).compact.uniq
        comment_ids = decoded.filter_map(&:first)
        [ticket_ids, comment_ids.empty? ? nil : comment_ids.uniq]
      end

      def decoded_synthetic_pairs(filter)
        Array(extract_field_lookup(filter.condition_tree, 'id'))
          .map { |sid| decode_synthetic_id(sid) }
      end

      def fetch_comments(ticket_ids, comment_ids)
        ticket_ids.flat_map do |ticket_id|
          comments = datasource.client.fetch_ticket_comments(ticket_id).map do |c|
            c.merge('ticket_id' => ticket_id)
          end
          comment_ids ? comments.select { |c| comment_ids.include?(c['id']) } : comments
        end
      end

      # Walks the (possibly-Branch) condition tree and collects equality/IN
      # values for `field`. Returns nil if no matching leaf was found.
      def extract_field_lookup(node, field)
        leaves = collect_leaves(node).select { |l| l.field == field }
        values = leaves.flat_map { |l| values_from_leaf(l) }
        values.empty? ? nil : values
      end

      def values_from_leaf(leaf)
        case leaf.operator
        when Operators::EQUAL then [leaf.value]
        when Operators::IN    then Array(leaf.value)
        else                       []
        end
      end

      def decode_synthetic_id(value)
        # Format: "<comment_id>-<ticket_id>". Both are positive integers.
        parts = value.to_s.split('-')
        return [nil, nil] unless parts.size == 2

        parts.map { |p| Integer(p, 10, exception: false) }
      end

      def collect_leaves(node)
        case node
        when Leaf   then [node]
        when Branch then node.conditions.flat_map { |c| collect_leaves(c) }
        else             []
        end
      end

      def define_schema
        # Synthetic composite primary key: a comment is only addressable in
        # the context of its parent ticket (Zendesk has no /comments/{id}
        # endpoint). We encode <comment_id>-<ticket_id> as a single String
        # PK because forest_admin_rails 1.26.2's URL constraint rejects '|'
        # (used by the toolkit's native pack_id for composite keys).
        add_field('id', ColumnSchema.new(column_type: 'String', filter_operators: [Operators::EQUAL, Operators::IN],
                                         is_primary_key: true, is_read_only: true, is_sortable: false))
        add_field('ticket_id', ColumnSchema.new(column_type: 'Number', filter_operators: [Operators::EQUAL, Operators::IN],
                                                is_read_only: true, is_sortable: false))
        add_field('author_id', ColumnSchema.new(column_type: 'Number', filter_operators: [],
                                                is_read_only: true, is_sortable: false))
        add_field('body', ColumnSchema.new(column_type: 'String', filter_operators: [],
                                           is_read_only: true, is_sortable: false))
        add_field('html_body', ColumnSchema.new(column_type: 'String', filter_operators: [],
                                                is_read_only: true, is_sortable: false))
        add_field('plain_body', ColumnSchema.new(column_type: 'String', filter_operators: [],
                                                 is_read_only: true, is_sortable: false))
        add_field('public', ColumnSchema.new(column_type: 'Boolean', filter_operators: [],
                                             is_read_only: true, is_sortable: false))
        add_field('type', ColumnSchema.new(column_type: 'String', filter_operators: [],
                                           is_read_only: true, is_sortable: false))
        add_field('via_channel', ColumnSchema.new(column_type: 'String', filter_operators: [],
                                                  is_read_only: true, is_sortable: false))
        add_field('created_at', ColumnSchema.new(column_type: 'Date', filter_operators: [],
                                                 is_read_only: true, is_sortable: false))
      end

      def define_relations
        add_field('author', ManyToOneSchema.new(
                              foreign_collection: 'ZendeskUser',
                              foreign_key: 'author_id',
                              foreign_key_target: 'id'
                            ))
        add_field('ticket', ManyToOneSchema.new(
                              foreign_collection: 'ZendeskTicket',
                              foreign_key: 'ticket_id',
                              foreign_key_target: 'id'
                            ))
      end

      def serialize(comment)
        attrs = attrs_of(comment)
        {
          'id' => "#{attrs["id"]}-#{attrs["ticket_id"]}",
          'ticket_id' => attrs['ticket_id'],
          'author_id' => attrs['author_id'],
          'body' => attrs['body'],
          'html_body' => attrs['html_body'],
          'plain_body' => attrs['plain_body'] || attrs['body'],
          'public' => attrs['public'],
          'type' => attrs['type'],
          'via_channel' => attrs.dig('via', 'channel') || attrs.dig(:via, :channel),
          'created_at' => attrs['created_at']
        }
      end
    end
  end
end
