module ForestAdminDatasourceIntercom
  module Collections
    class Conversation < CursorCollection
      # One Intercom conversation flattened into the row the schema declares.
      # Nothing here reads a sub-resource: every value comes from the payload the
      # listing already returned.
      module Serializer
        protected

        def serialize(conversation)
          attrs = conversation.is_a?(Hash) ? conversation : {}

          native(attrs)
            .merge(contacts_of(attrs))
            .merge(source_of(attrs['source']))
            .merge(statistics_of(attrs['statistics']))
        end

        private

        def native(attrs)
          company = attrs['company'].is_a?(Hash) ? attrs['company'] : {}

          {
            'id' => stringify_id(attrs['id']),
            'title' => attrs['title'],
            'state' => attrs['state'],
            'priority' => attrs['priority'],
            'open' => attrs['open'],
            'read' => attrs['read'],
            'created_at' => stamp(attrs['created_at']),
            'updated_at' => stamp(attrs['updated_at']),
            'waiting_since' => stamp(attrs['waiting_since']),
            'snoozed_until' => stamp(attrs['snoozed_until']),
            'admin_assignee_id' => stringify_id(attrs['admin_assignee_id']),
            'team_assignee_id' => stringify_id(attrs['team_assignee_id']),
            'company_id' => stringify_id(company['id']),
            'company_name' => company['name'],
            'tag_names' => nested_list(attrs['tags'], 'tags').filter_map { |tag| tag['name'] if tag.is_a?(Hash) },
            'ai_agent_participated' => attrs['ai_agent_participated']
          }
        end

        # A group conversation carries several contacts. The row names the first
        # and counts them, rather than presenting one of several as the one.
        def contacts_of(attrs)
          ids = nested_list(attrs['contacts'], 'contacts').filter_map { |contact| stringify_id(contact['id']) }

          { 'contact_ids' => ids, 'contact_count' => ids.size,
            # Filled by the bulk read of `enrich`, and left nil when the
            # projection did not ask for them.
            'contact_name' => nil, 'contact_email' => nil }
        end

        def source_of(source)
          attrs = source.is_a?(Hash) ? source : {}
          author = attrs['author'].is_a?(Hash) ? attrs['author'] : {}

          { 'source_type' => attrs['type'],
            'source_subject' => attrs['subject'],
            # Plaintext, because `display_as=plaintext` rides on every read: the
            # bodies are HTML written by end customers.
            'source_body' => attrs['body'],
            'source_author_name' => author['name'],
            'source_author_email' => author['email'],
            'source_delivered_as' => attrs['delivered_as'] }
        end

        # `statistics` is null on a conversation Intercom has computed nothing
        # for yet; every column then reads as absent rather than as zero.
        def statistics_of(statistics)
          attrs = statistics.is_a?(Hash) ? statistics : {}

          { 'closed_at' => stamp(attrs['last_close_at']),
            'first_closed_at' => stamp(attrs['first_close_at']),
            'closed_by_id' => stringify_id(attrs['last_closed_by_id']),
            'first_contact_reply_at' => stamp(attrs['first_contact_reply_at']),
            'last_contact_reply_at' => stamp(attrs['last_contact_reply_at']),
            'last_admin_reply_at' => stamp(attrs['last_admin_reply_at']),
            'reopen_count' => attrs['count_reopens'],
            'part_count' => attrs['count_conversation_parts'] }
        end

        # Intercom nests its lists twice -- `{"type": "contact.list", "contacts":
        # [...]}` -- and answers a null instead of an empty list when there is
        # nothing.
        def nested_list(container, key)
          return [] unless container.is_a?(Hash)

          list = container[key]
          list.is_a?(Array) ? list : []
        end

        def first_contact_id(record)
          contact = nested_list((record || {})['contacts'], 'contacts').first
          contact.is_a?(Hash) ? stringify_id(contact['id']) : nil
        end
      end
    end
  end
end
