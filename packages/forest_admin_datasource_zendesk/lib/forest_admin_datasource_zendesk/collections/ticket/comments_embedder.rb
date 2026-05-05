module ForestAdminDatasourceZendesk
  module Collections
    class Ticket < BaseCollection
      module CommentsEmbedder
        private

        def want_comments?(projection)
          projection.nil? ||
            Array(projection).map(&:to_s).any? { |p| p == 'comments' || p.start_with?('comments:') }
        end

        def embed_comments(records, rows)
          comments_by_ticket = records.to_h do |t|
            id = attrs_of(t)['id']
            [id, datasource.client.fetch_ticket_comments(id)]
          end
          author_ids = comments_by_ticket.values.flatten.filter_map { |c| c['author_id'] }.uniq
          users = datasource.client.fetch_users_by_ids(author_ids)
          rows.each_with_index do |row, i|
            row['comments'] = comments_by_ticket[attrs_of(records[i])['id']].map { |c| serialize_comment(c, users) }
          end
        end

        def serialize_comment(comment, users)
          author = users[comment['author_id']]
          author_attrs = author && (author.is_a?(Hash) ? author : attrs_of(author))
          {
            'id' => comment['id'],
            'body' => comment['body'],
            'html_body' => comment['html_body'],
            'public' => comment['public'],
            'author_email' => author_attrs && author_attrs['email'],
            'author_name' => author_attrs && author_attrs['name'],
            'created_at' => comment['created_at']
          }
        end
      end
    end
  end
end
