module ForestAdminDatasourceZendesk
  module Collections
    class Ticket < BaseCollection
      # Bulk-loads requester/assignee/organization records from the source
      # tickets and writes them back onto the projected rows by index.
      module RelationEmbedder
        private

        def embed_relations(records, rows, projection)
          return if projection.nil?

          relations = relations_in(projection)
          return if relations.empty?

          sources = records.map { |t| attrs_of(t) }
          embed_users(rows, sources, relations) if (relations & %w[requester assignee]).any?
          embed_organizations(rows, sources) if relations.include?('organization')
        end

        def embed_users(rows, sources, relations)
          ids = sources.flat_map { |a| [a['requester_id'], a['assignee_id']] }.compact.uniq
          users = datasource.client.fetch_users_by_ids(ids)
          rows.each_with_index do |row, i|
            row['requester'] = serialized_user(users[sources[i]['requester_id']]) if relations.include?('requester')
            row['assignee']  = serialized_user(users[sources[i]['assignee_id']]) if relations.include?('assignee')
          end
        end

        def embed_organizations(rows, sources)
          ids = sources.filter_map { |a| a['organization_id'] }.uniq
          orgs = datasource.client.fetch_organizations_by_ids(ids)
          rows.each_with_index do |row, i|
            row['organization'] = serialized_org(orgs[sources[i]['organization_id']])
          end
        end

        def relations_in(projection)
          Array(projection).map(&:to_s).filter_map { |p| p.split(':').first if p.include?(':') }.uniq
        end

        def serialized_user(raw)
          return nil if raw.nil?

          attrs = raw.is_a?(Hash) ? raw : attrs_of(raw)
          {
            'id' => attrs['id'], 'email' => attrs['email'], 'name' => attrs['name'],
            'role' => attrs['role'], 'organization_id' => attrs['organization_id'],
            'phone' => attrs['phone'], 'time_zone' => attrs['time_zone'],
            'locale' => attrs['locale'], 'verified' => attrs['verified'],
            'suspended' => attrs['suspended'], 'created_at' => attrs['created_at'],
            'updated_at' => attrs['updated_at']
          }
        end

        def serialized_org(raw)
          return nil if raw.nil?

          attrs = raw.is_a?(Hash) ? raw : attrs_of(raw)
          {
            'id' => attrs['id'], 'name' => attrs['name'],
            'domain_names' => attrs['domain_names'], 'details' => attrs['details'],
            'notes' => attrs['notes'], 'group_id' => attrs['group_id'],
            'shared_tickets' => attrs['shared_tickets'],
            'created_at' => attrs['created_at'], 'updated_at' => attrs['updated_at']
          }
        end
      end
    end
  end
end
