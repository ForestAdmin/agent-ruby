module ForestAdminDatasourceIntercom
  module Collections
    # The thread of a conversation or ticket. `part_type` is kept, and internal notes are included next to
    # customer replies -- that is what a thread is on Intercom. Intercom keeps only the 500 most recent parts.
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
