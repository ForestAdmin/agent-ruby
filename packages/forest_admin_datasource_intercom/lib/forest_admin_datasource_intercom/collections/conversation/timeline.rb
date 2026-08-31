module ForestAdminDatasourceIntercom
  module Collections
    class Conversation < CursorCollection
      # The thread of a conversation, as a structured list the record view can
      # render: who said what, when, and through which kind of event.
      #
      # Two things this exists to get right. The opening message lives in
      # `source`, not in the parts -- a timeline built from the parts alone opens
      # on the first reply and loses what the customer actually asked. And
      # `part_type` is kept on every entry: an assignment, a note and a reply are
      # not the same event, and a thread that flattens them reads as a
      # conversation that never happened the way it did.
      #
      # Intercom caps a conversation at its 500 most recent parts; the entry
      # count is therefore what is in hand, not necessarily what exists.
      module Timeline
        # The pseudo type of the opening entry. Not an Intercom part type: it is
        # the source, and calling it `comment` would make it indistinguishable
        # from the replies that follow.
        SOURCE_PART_TYPE = 'conversation_started'.freeze

        private

        def build_timeline(conversation)
          attrs = conversation.is_a?(Hash) ? conversation : {}
          entries = [source_entry(attrs)].compact

          entries + (parts_of(attrs) || []).map { |part| part_entry(part) }
        end

        # nil rather than an empty list when the payload carries no parts at all:
        # a listing response has none, and reading that as "this conversation is
        # empty" is exactly the answer that looks complete without being it.
        def parts_of(conversation)
          container = (conversation || {})['conversation_parts']
          return nil unless container.is_a?(Hash)

          parts = container['conversation_parts']
          parts.is_a?(Array) ? parts : nil
        end

        def source_entry(attrs)
          source = attrs['source']
          return nil unless source.is_a?(Hash)

          entry(part_type: SOURCE_PART_TYPE, created_at: attrs['created_at'], author: source['author'],
                body: source['body'], attachments: source['attachments'])
            .merge('id' => stringify_id(source['id']))
        end

        def part_entry(part)
          attrs = part.is_a?(Hash) ? part : {}

          entry(part_type: attrs['part_type'], created_at: attrs['created_at'], author: attrs['author'],
                body: attrs['body'], attachments: attrs['attachments'])
            .merge('id' => stringify_id(attrs['id']), 'redacted' => attrs['redacted'])
        end

        def entry(part_type:, created_at:, author:, body:, attachments:)
          writer = author.is_a?(Hash) ? author : {}

          { 'part_type' => part_type,
            'created_at' => stamp(created_at),
            'author_type' => writer['type'],
            'author_name' => writer['name'],
            'author_email' => writer['email'],
            'body' => body,
            'attachment_count' => Array(attachments).size }
        end
      end
    end
  end
end
