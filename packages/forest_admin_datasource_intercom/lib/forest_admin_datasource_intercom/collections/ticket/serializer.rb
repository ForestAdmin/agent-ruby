module ForestAdminDatasourceIntercom
  module Collections
    class Ticket < CursorCollection
      # One Intercom ticket flattened into the row the schema declares. Nothing
      # here reads a sub-resource: the state, the type and the attributes all
      # travel with the ticket.
      module Serializer
        protected

        def serialize(ticket)
          attrs = ticket.is_a?(Hash) ? ticket : {}

          native(attrs)
            .merge(state_of(attrs))
            .merge(type_of(attrs['ticket_type']))
            .merge(contact_columns_for(attrs))
            .merge(attribute_values_of(attrs['ticket_attributes']))
            .merge(derived_columns_for(attrs))
        end

        private

        def native(attrs)
          { 'id' => stringify_id(attrs['id']),
            'ticket_id' => stringify_id(attrs['ticket_id']),
            'category' => attrs['category'],
            'open' => attrs['open'],
            'is_shared' => attrs['is_shared'],
            'created_at' => stamp(attrs['created_at']),
            'updated_at' => stamp(attrs['updated_at']),
            'admin_assignee_id' => stringify_id(attrs['admin_assignee_id']),
            'team_assignee_id' => stringify_id(attrs['team_assignee_id']),
            'company_id' => stringify_id(attrs['company_id']),
            'part_count' => parts_total(attrs) }
        end

        def state_of(attrs)
          state = attrs['ticket_state'].is_a?(Hash) ? attrs['ticket_state'] : {}

          # `internal_label` is what the support team reads. The category and the
          # customer-facing label are a hop away, on the `state` relation.
          { 'state_id' => stringify_id(state['id']),
            'state_label' => state['internal_label'],
            'previous_state_id' => stringify_id(attrs['previous_ticket_state_id']) }
        end

        def type_of(ticket_type)
          attrs = ticket_type.is_a?(Hash) ? ticket_type : {}

          { 'ticket_type_id' => stringify_id(attrs['id']), 'ticket_type_name' => attrs['name'] }
        end

        # Intercom keys the values by attribute **name**, which is what lets a
        # single collection display the union of every type's attributes -- and
        # what stops it from filtering on them, since the filter is written by id
        # and the id differs from one type to the next.
        #
        # The value is read under the name the workspace gave it and written
        # under the column name the schema publishes; the two differ whenever the
        # first could not travel through a Forest query string.
        #
        # A ticket of another type simply does not carry the key: the column
        # reads as absent rather than as empty.
        def attribute_values_of(values)
          held = values.is_a?(Hash) ? values : {}

          attribute_columns.to_h { |attribute| [attribute.column_name, coerce(held[attribute.name], attribute)] }
        end

        # A date attribute comes back as epoch seconds like every other Intercom
        # date; the rest is handed over as it came.
        def coerce(value, attribute)
          return nil if value.nil?
          return stamp(value) if attribute.column_type == 'Date' && value.is_a?(Numeric)

          value
        end
      end
    end
  end
end
