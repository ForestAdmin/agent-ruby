module ForestAdminDatasourceZendesk
  module Collections
    # Comments are *always* fetched in the context of a parent ticket
    # (Zendesk: GET /tickets/{id}/comments). The collection only supports
    # filters of the form `ticket_id = N` or `ticket_id IN [...]`. Anything
    # else raises ForestException.
    class Comment < BaseCollection
      ManyToOneSchema = ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema

      def initialize(datasource)
        super(datasource, 'ZendeskComment')
        define_schema
        define_relations
      end

      def list(_caller, filter, projection)
        synthetic_ids = extract_field_lookup(filter.condition_tree, 'id')
        ticket_ids    = extract_field_lookup(filter.condition_tree, 'ticket_id') || []
        comment_ids   = []

        Array(synthetic_ids).each do |sid|
          c_id, t_id = decode_synthetic_id(sid)
          comment_ids << c_id if c_id
          ticket_ids << t_id  if t_id
        end

        ticket_ids.uniq!
        comment_ids = comment_ids.empty? ? nil : comment_ids.uniq

        # Top-level browse with no ticket scope -> return []. Zendesk has no
        # /comments listing endpoint; legitimate access (Ticket -> comments
        # relation, show route via synthetic id) always carries a ticket_id.
        if ticket_ids.empty?
          ForestAdminDatasourceZendesk.logger.info(
            '[forest_admin_datasource_zendesk] ZendeskComment.list called without a ticket scope; ' \
            'returning [] (use the Ticket -> comments relation to fetch comments)'
          )
          return []
        end

        records = ticket_ids.flat_map do |ticket_id|
          comments = datasource.client.fetch_ticket_comments(ticket_id).map do |c|
            c.merge('ticket_id' => ticket_id)
          end
          comment_ids ? comments.select { |c| comment_ids.include?(c['id']) } : comments
        end

        records.map { |c| project(serialize(c), projection) }
      end

      # Counts are deactivated for comments — Zendesk doesn't expose a count
      # endpoint for ticket comments, and the list endpoint already returns
      # everything in a single response.

      private

      Branch = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeBranch

      # Walks the (possibly-Branch) condition tree and collects equality/IN
      # values for `field`. Returns nil if no matching leaf was found.
      def extract_field_lookup(node, field)
        leaves = collect_leaves(node).select { |l| l.field == field }
        return nil if leaves.empty?

        values = leaves.flat_map do |leaf|
          case leaf.operator
          when Operators::EQUAL then [leaf.value]
          when Operators::IN    then Array(leaf.value)
          else                       []
          end
        end

        values.empty? ? nil : values
      end

      def decode_synthetic_id(value)
        # Format: "<comment_id>-<ticket_id>". Both are positive integers.
        parts = value.to_s.split('-')
        return [nil, nil] unless parts.size == 2

        c_id, t_id = parts.map { |p| Integer(p, 10) rescue nil }
        [c_id, t_id]
      end

      def collect_leaves(node)
        case node
        when Leaf   then [node]
        when Branch then node.conditions.flat_map { |c| collect_leaves(c) }
        else             []
        end
      end

      def define_schema
        # Synthetic composite primary key: a comment is only addressable in the
        # context of its parent ticket (Zendesk has no /comments/{id} endpoint).
        # We encode <comment_id>-<ticket_id> as a single String PK because
        # forest_admin_rails 1.26.2's URL constraint rejects '|' (used by the
        # toolkit's native pack_id for composite keys). Forest URL becomes
        # /ZendeskComment/<comment_id>-<ticket_id>; filter on `id` carries the
        # full synthetic value, which we decode in #list.
        add_field('id',         ColumnSchema.new(column_type: 'String', filter_operators: [Operators::EQUAL, Operators::IN],
                                                  is_primary_key: true, is_read_only: true, is_sortable: false))
        add_field('ticket_id',  ColumnSchema.new(column_type: 'Number', filter_operators: [Operators::EQUAL, Operators::IN],
                                                  is_read_only: true, is_sortable: false))
        add_field('author_id',  ColumnSchema.new(column_type: 'Number', filter_operators: [],
                                                  is_read_only: true, is_sortable: false))
        add_field('body',       ColumnSchema.new(column_type: 'String', filter_operators: [],
                                                  is_read_only: true, is_sortable: false))
        add_field('html_body',  ColumnSchema.new(column_type: 'String', filter_operators: [],
                                                  is_read_only: true, is_sortable: false))
        add_field('plain_body', ColumnSchema.new(column_type: 'String', filter_operators: [],
                                                  is_read_only: true, is_sortable: false))
        add_field('public',     ColumnSchema.new(column_type: 'Boolean', filter_operators: [],
                                                  is_read_only: true, is_sortable: false))
        add_field('type',       ColumnSchema.new(column_type: 'String', filter_operators: [],
                                                  is_read_only: true, is_sortable: false))
        add_field('via_channel', ColumnSchema.new(column_type: 'String', filter_operators: [],
                                                   is_read_only: true, is_sortable: false))
        add_field('created_at', ColumnSchema.new(column_type: 'Date',   filter_operators: [],
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
          'id'          => "#{attrs['id']}-#{attrs['ticket_id']}",
          'ticket_id'   => attrs['ticket_id'],
          'author_id'   => attrs['author_id'],
          'body'        => attrs['body'],
          'html_body'   => attrs['html_body'],
          'plain_body'  => attrs['plain_body'] || attrs['body'],
          'public'      => attrs['public'],
          'type'        => attrs['type'],
          'via_channel' => (attrs.dig('via', 'channel') || attrs.dig(:via, :channel)),
          'created_at'  => attrs['created_at']
        }
      end
    end
  end
end
