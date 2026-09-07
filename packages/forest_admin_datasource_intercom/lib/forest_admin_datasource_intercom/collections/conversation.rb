module ForestAdminDatasourceIntercom
  module Collections
    # The conversations of the workspace: what a support team actually works on.
    #
    # Read through `GET /conversations`, whose records Intercom puts under
    # `conversations` rather than under the `data` envelope -- `/tickets/search`
    # does the same with `tickets`, so the key is named rather than assumed.
    #
    # `display_as=plaintext` on every read: the bodies are HTML written by end
    # customers, and rendering third-party HTML inside Forest is neither safe nor
    # useful (R10).
    # Long by line count only: most of it declares the columns, one call each.
    class Conversation < CursorCollection # rubocop:disable Metrics/ClassLength
      include ContactIdentity
      include Conversation::Serializer
      include Conversation::Timeline

      # How many conversations of one page may have their timeline read. The
      # parts are absent from the listing response -- Intercom returns them only
      # when retrieving a single conversation -- so a timeline asked for in a
      # list view costs one request per row. Bounded rather than turned into a
      # page the operator waits half a minute for; rows past the cap are left at
      # nil, which reads as "unknown", never as "this conversation is empty".
      MAX_TIMELINE_READS = 10

      def initialize(datasource)
        super(datasource, 'IntercomConversation')
        # The one collection of this datasource Intercom matches text on: `~` on
        # `source.body`, which is the message that opened the conversation.
        enable_search
      end

      protected

      def list_endpoint = 'conversations'
      def list_key = 'conversations'
      def searchable = 'conversations'
      def search_column = 'source_body'

      # Sent on the search too, where Intercom does not document it: the bodies
      # are HTML written by end customers (R10), and a parameter it ignores costs
      # a query string while the one it honours saves every filtered row from
      # coming back as markup.
      def read_params = { 'display_as' => 'plaintext' }

      # The contact identity and the timeline, each read only when the projection
      # names it: neither is on the conversation payload, and a page that never
      # asked for them must not pay for them.
      def enrich(records, rows, projection)
        wanted = Array(projection).map(&:to_s)

        embed_contact_identity(records, rows, wanted)
        embed_timeline(records, rows, wanted)
      end

      private

      def define_schema
        add_column('id', 'String', is_primary_key: true)
        add_column('title', 'String')
        # Left plain strings rather than enums: the values a workspace really
        # serves are worth measuring before the interface offers them as a
        # closed list, and nothing filters on them in this lot anyway.
        add_column('state', 'String')
        add_column('priority', 'String')
        add_column('open', 'Boolean')
        add_column('read', 'Boolean')
        add_column('created_at', 'Date')
        add_column('updated_at', 'Date')
        add_column('waiting_since', 'Date')
        add_column('snoozed_until', 'Date')
        define_assignment_columns
        define_contact_columns
        define_source_columns
        define_statistics_columns
        add_column('tag_names', 'Json')
        add_column('ai_agent_participated', 'Boolean')
        add_column('timeline', 'Json')
        define_relations
      end

      # Who the conversation sits with, and who closed it. All three targets are
      # read whole in one request, and `/conversations/search` takes a filter on
      # each of the three keys -- so these relations can be read, navigated and
      # filtered through alike.
      #
      # No relation towards the company: a conversation carries its account as a
      # whole object, so the name is already on the row, and the Companies
      # collection arrives with lot 4.
      def define_relations
        add_many_to_one('admin_assignee', foreign_collection: 'IntercomAdmin', foreign_key: 'admin_assignee_id')
        add_many_to_one('team_assignee', foreign_collection: 'IntercomTeam', foreign_key: 'team_assignee_id')
        add_many_to_one('closed_by', foreign_collection: 'IntercomAdmin', foreign_key: 'closed_by_id')
      end

      # Who the conversation sits with, and which account it belongs to. The
      # conversation carries its company as a whole object, so the account name
      # is free here -- unlike on a ticket, which carries the id alone.
      def define_assignment_columns
        add_column('admin_assignee_id', 'String')
        add_column('team_assignee_id', 'String')
        add_column('company_id', 'String')
        add_column('company_name', 'String')
      end

      # The contact identity is denormalized onto the row rather than declared as
      # a relation: the Contacts collection arrives in lot 4, and a relation whose
      # target collection is missing is a schema the agent refuses to boot on.
      #
      # A group conversation has several contacts; the row carries the first and
      # says how many there are, rather than pretending there is one.
      def define_contact_columns
        add_column('contact_ids', 'Json')
        add_column('contact_count', 'Number')
        add_column('contact_name', 'String')
        add_column('contact_email', 'String')
      end

      # The message that opened the conversation lives in `source`, not in the
      # parts. A timeline built from the parts alone loses it, which is the one
      # message nobody opens a conversation without wanting to read.
      def define_source_columns
        add_column('source_type', 'String')
        add_column('source_subject', 'String')
        add_column('source_body', 'String')
        add_column('source_author_name', 'String')
        add_column('source_author_email', 'String')
        add_column('source_delivered_as', 'String')
      end

      # Intercom keeps the lifecycle of a conversation in `statistics`, which is
      # where the closure date and the reply timestamps come from. Flattened onto
      # the row: they cost nothing, they are exact, and they are what an ops lead
      # reads a queue for.
      def define_statistics_columns
        add_column('closed_at', 'Date')
        add_column('first_closed_at', 'Date')
        add_column('closed_by_id', 'String')
        add_column('first_contact_reply_at', 'Date')
        add_column('last_contact_reply_at', 'Date')
        add_column('last_admin_reply_at', 'Date')
        add_column('reopen_count', 'Number')
        add_column('part_count', 'Number')
      end

      # A record read through the record endpoint already carries its parts, so
      # its timeline is free; one read from the listing does not, and pays a
      # request. Rows past the cap keep the nil the projection put there.
      def embed_timeline(records, rows, projection)
        return unless projection.include?('timeline')

        budget = MAX_TIMELINE_READS
        missing = 0

        records.each_with_index do |record, index|
          if parts_of(record)
            rows[index]['timeline'] = build_timeline(record)
          elsif budget.positive?
            budget -= 1
            detail = read_detail(record['id'])
            rows[index]['timeline'] = detail && build_timeline(detail)
          else
            missing += 1
          end
        end

        warn_truncated_timelines(missing) if missing.positive?
      end

      def read_detail(id)
        client.fetch_record(list_endpoint, id, params: read_params)
      rescue APIError => e
        raise unless e.status == 404

        nil
      end

      def warn_truncated_timelines(missing)
        ForestAdminDatasourceIntercom.logger.warn(
          "[forest_admin_datasource_intercom] #{name} left the timeline of #{missing} row(s) unread: Intercom " \
          'returns the parts only when retrieving one conversation, so a list view pays a request per row and ' \
          "this reads at most #{MAX_TIMELINE_READS}. Those rows show no timeline rather than an empty one."
        )
      end
    end
  end
end
