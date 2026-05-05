module ForestAdminDatasourceZendesk
  module Collections
    class Ticket < BaseCollection
      module Serializer
        private

        def serialize(ticket, emails = {})
          attrs = attrs_of(ticket)
          result = base_attributes(attrs, emails)
          cf_values = Array(attrs['custom_fields']).to_h { |f| [f['id'], f['value']] }
          @custom_fields.each { |cf| result[cf[:column_name]] = cf_values[cf[:zendesk_id]] }
          result
        end

        def base_attributes(attrs, emails)
          {
            'id' => attrs['id'], 'subject' => attrs['subject'],
            'description' => attrs['description'], 'status' => attrs['status'],
            'priority' => attrs['priority'], 'ticket_type' => attrs['type'],
            'requester_id' => attrs['requester_id'], 'assignee_id' => attrs['assignee_id'],
            'group_id' => attrs['group_id'], 'organization_id' => attrs['organization_id'],
            'external_id' => attrs['external_id'],
            'requester_email' => emails[attrs['requester_id']],
            'tags' => attrs['tags'], 'url' => attrs['url'],
            'created_at' => attrs['created_at'], 'updated_at' => attrs['updated_at']
          }
        end
      end
    end
  end
end
