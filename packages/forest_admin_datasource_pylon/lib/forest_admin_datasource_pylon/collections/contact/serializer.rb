module ForestAdminDatasourcePylon
  module Collections
    class Contact < CursorCollection
      module Serializer
        NATIVE_FIELDS = %w[id name email emails primary_phone_number phone_numbers avatar_url
                           portal_role portal_role_id external_ids integration_user_ids].freeze

        private

        def serialize(contact)
          attrs = contact.is_a?(Hash) ? contact : {}
          record = NATIVE_FIELDS.to_h { |field| [field, attrs[field]] }
          record['account_id'] = nested_id(attrs['account'])
          add_custom_field_values(record, attrs['custom_fields'])
          record
        end
      end
    end
  end
end
