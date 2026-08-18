module ForestAdminDatasourcePylon
  module Collections
    class Issue < BaseCollection
      # The conversation of an issue, embedded as a structured array column the
      # way the Zendesk datasource embeds a ticket's comments.
      #
      # Pylon has no way to read the threads of several issues at once, so the
      # thread costs one request per row — against an endpoint allowing 20 per
      # minute. The fan-out is therefore bounded like the primary-key lookups of
      # this collection: truncated with a warning rather than turned into a rate
      # limit error halfway through the page. A relation the projection does not
      # ask for costs no request at all.
      module MessagesEmbedder
        include RecordSerialization

        private

        # The thread is read only when the projection names it. A nil projection
        # — what a count or an export goes through — asks for the record as
        # Pylon returns it, and embeds nothing, exactly like RelationEmbedder:
        # spending one request per row on a path that never asked for the
        # conversation is the very fan-out MAX_MESSAGE_EMBEDS exists to bound.
        def want_messages?(projection)
          Array(projection).map(&:to_s).any? { |p| p == 'messages' || p.start_with?('messages:') }
        end

        # A row past the cap, and a row whose thread failed to be read, are left
        # at nil: "unknown", never the empty list, which would read as "this
        # issue has no message" — the kind of answer that looks complete without
        # being it.
        def embed_messages(records, rows)
          embedded = rows.first(MAX_MESSAGE_EMBEDS)
          warn_truncated_threads(rows.size) if rows.size > embedded.size

          embedded.each_with_index do |row, index|
            messages = datasource.client.fetch_issue_messages(records[index]['id'])
            row['messages'] = messages&.map { |message| serialize_message(message) }
          end
        end

        def serialize_message(message)
          attrs = message.is_a?(Hash) ? message : {}

          {
            'id' => attrs['id'],
            'body_html' => attrs['message_html'],
            'is_private' => attrs['is_private'],
            'source' => attrs['source'],
            'thread_id' => attrs['thread_id'],
            'file_urls' => attrs['file_urls'],
            'created_at' => attrs['timestamp']
          }.merge(flatten_author(attrs['author']))
        end

        # Pylon nests the author's contact and user sides side by side, both
        # optional and with nothing telling them apart: a message written by an
        # agent carries `user`, one written by a customer carries `contact`. Both
        # ids are kept, so a message stays traceable to the PylonContact or
        # PylonUser record it came from, and the email is taken from whichever
        # side is there.
        def flatten_author(author)
          attrs   = author.is_a?(Hash) ? author : {}
          contact = attrs['contact']
          user    = attrs['user']

          {
            'author_name' => attrs['name'],
            'author_avatar_url' => attrs['avatar_url'],
            'author_email' => nested_email(contact) || nested_email(user),
            'author_contact_id' => nested_id(contact),
            'author_user_id' => nested_id(user)
          }
        end

        def nested_email(value)
          value['email'] if value.is_a?(Hash)
        end

        def warn_truncated_threads(asked)
          ForestAdminDatasourcePylon.logger.warn(
            "[forest_admin_datasource_pylon] Asked for the message thread of #{asked} issues, reading the first " \
            "#{MAX_MESSAGE_EMBEDS}: one request per issue would exhaust the rate limit of the agent. " \
            'Narrow the selection, or take the thread out of the projection, to reach the records past this point.'
          )
        end
      end
    end
  end
end
