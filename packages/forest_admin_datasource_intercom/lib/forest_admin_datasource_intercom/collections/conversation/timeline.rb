module ForestAdminDatasourceIntercom
  module Collections
    class Conversation < CursorCollection
      # What a conversation adds to the shared thread: where its parts live, and
      # the entry that opens it.
      #
      # The opening message lives in `source`, not in the parts -- a timeline
      # built from the parts alone opens on the first reply and loses what the
      # customer actually asked.
      module Timeline
        # The pseudo type of the opening entry. Not an Intercom part type: it is
        # the source, and calling it `comment` would make it indistinguishable
        # from the replies that follow.
        SOURCE_PART_TYPE = 'conversation_started'.freeze

        private

        # nil rather than an empty list when the payload carries no parts at all:
        # a listing response has none, and reading that as "this conversation is
        # empty" is exactly the answer that looks complete without being it.
        def parts_of(conversation)
          container = (conversation || {})['conversation_parts']
          return nil unless container.is_a?(Hash)

          parts = container['conversation_parts']
          parts.is_a?(Array) ? parts : nil
        end

        def opening_entry(attrs)
          source = attrs['source']
          return nil unless source.is_a?(Hash)

          entry(part_type: SOURCE_PART_TYPE, created_at: attrs['created_at'], author: source['author'],
                body: source['body'], attachments: source['attachments'])
            .merge('id' => stringify_id(source['id']))
        end
      end
    end
  end
end
