module ForestAdminDatasourceIntercom
  module Collections
    # The thread of a conversation or of a ticket, as a structured list the
    # record view can render: who said what, when, and through which kind of
    # event.
    #
    # `part_type` is kept on every entry: an assignment, an internal note and a
    # reply are not the same event, and a thread that flattens them reads as an
    # exchange that never happened the way it did. Which also means **the
    # internal notes of the team are in there**, alongside what the customer
    # was told -- that is what a thread is on Intercom, and hiding half of it
    # would be the more surprising answer.
    #
    # Intercom keeps the 500 most recent parts of either resource, so the entry
    # count is what is in hand, never necessarily what exists. The two
    # collections differ in where they read those parts and in whether anything
    # opens the thread before them -- both are hooks.
    module Timeline
      private

      def build_timeline(entity)
        attrs = entity.is_a?(Hash) ? entity : {}

        [opening_entry(attrs)].compact + (parts_of(attrs) || []).map { |part| part_entry(part) }
      end

      # What comes before the parts. A conversation opens on its `source`, which
      # is not a part at all; a ticket opens on its first part like any other
      # event, so there is nothing to prepend.
      def opening_entry(_attrs) = nil

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
