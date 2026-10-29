module ForestAdminDatasourceIntercom
  module Collections
    class Company < OffsetCollection
      # One Intercom company flattened into the row the schema declares.
      module Serializer
        protected

        def serialize(company)
          attrs = company.is_a?(Hash) ? company : {}
          plan = attrs['plan'].is_a?(Hash) ? attrs['plan'] : {}

          identity(attrs).merge(
            'plan_name' => plan['name'],
            'user_count' => attrs['user_count'],
            'session_count' => attrs['session_count']
          ).merge(dates_of(attrs)).merge(attribute_values(attrs['custom_attributes']))
        end

        private

        def identity(attrs)
          {
            'id' => stringify_id(attrs['id']),
            'company_id' => stringify_id(attrs['company_id']),
            'name' => attrs['name'],
            'size' => attrs['size'],
            'industry' => attrs['industry'],
            'website' => attrs['website'],
            'monthly_spend' => attrs['monthly_spend']
          }
        end

        def dates_of(attrs)
          {
            'created_at' => stamp(attrs['created_at']),
            'updated_at' => stamp(attrs['updated_at']),
            'last_request_at' => stamp(attrs['last_request_at']),
            'remote_created_at' => stamp(attrs['remote_created_at'])
          }
        end
      end
    end
  end
end
