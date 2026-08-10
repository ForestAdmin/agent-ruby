module ForestAdminDatasourcePylon
  module Collections
    class Issue < BaseCollection
      module Serializer
        PARTY_FIELDS = { 'account_id' => 'account', 'requester_id' => 'requester',
                         'assignee_id' => 'assignee', 'team_id' => 'team' }.freeze

        NATIVE_FIELDS = %w[id number link title body_html state type source tags
                           customer_portal_visible author_unverified number_of_touches
                           first_response_time resolution_time latest_message_time
                           created_at updated_at time_in_status_seconds
                           business_hours_time_in_status_seconds].freeze

        private

        def serialize(issue)
          attrs = issue.is_a?(Hash) ? issue : {}
          record = NATIVE_FIELDS.to_h { |field| [field, attrs[field]] }
          PARTY_FIELDS.each { |column, source| record[column] = nested_id(attrs[source]) }
          add_custom_field_values(record, attrs['custom_fields'])
          record
        end

        def nested_id(value)
          value['id'] if value.is_a?(Hash)
        end

        def add_custom_field_values(record, values)
          custom_fields.each do |cf|
            entry = values.is_a?(Hash) ? values[cf[:column_name]] : nil
            record[cf[:column_name]] = custom_field_value(entry)
          end
        end

        # Pylon spells a custom field as `slug => {"slug": ..., "value": ...}`,
        # with `"values": [...]` instead of `"value"` for multi-value fields.
        def custom_field_value(entry)
          return entry unless entry.is_a?(Hash)

          entry.key?('value') ? entry['value'] : entry['values']
        end
      end
    end
  end
end
