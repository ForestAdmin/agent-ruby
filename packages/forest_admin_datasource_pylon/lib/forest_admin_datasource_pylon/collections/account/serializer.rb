module ForestAdminDatasourcePylon
  module Collections
    class Account < CursorCollection
      module Serializer
        NATIVE_FIELDS = %w[id name type is_disabled domain primary_domain domains tags external_ids
                           channels crm_settings created_at updated_at
                           latest_customer_activity_time].freeze

        private

        def serialize(account)
          attrs = account.is_a?(Hash) ? account : {}
          record = NATIVE_FIELDS.to_h { |field| [field, attrs[field]] }
          record['owner_id'] = nested_id(attrs['owner'])
          add_custom_field_values(record, attrs['custom_fields'])
          record
        end
      end
    end
  end
end
