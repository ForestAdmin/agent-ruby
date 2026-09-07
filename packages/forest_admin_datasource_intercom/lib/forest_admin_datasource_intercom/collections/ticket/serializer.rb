module ForestAdminDatasourceIntercom
  module Collections
    class Ticket < CursorCollection
      # One Intercom ticket flattened into the row the schema declares. Nothing
      # here reads a sub-resource: the state, the type and the attributes all
      # travel with the ticket.
      module Serializer
        protected

        # Intercom keys the attribute values by **name**, which is what lets a
        # single collection display the union of every ticket type's -- and what
        # stops it from filtering on them, the filter being written by an id
        # that differs from one type to the next. A ticket of another type
        # simply does not carry the key, and the column reads as empty.
        def serialize(ticket)
          attrs = ticket.is_a?(Hash) ? ticket : {}

          native(attrs)
            .merge(state_of(attrs))
            .merge(type_of(attrs['ticket_type']))
            .merge(contact_columns_for(attrs))
            .merge(attribute_values(attrs['ticket_attributes']))
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
      end
    end
  end
end
