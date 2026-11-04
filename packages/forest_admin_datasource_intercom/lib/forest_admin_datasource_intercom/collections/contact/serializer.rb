module ForestAdminDatasourceIntercom
  module Collections
    class Contact < CursorCollection
      # One Intercom contact flattened into the row the schema declares.
      # Nothing here reads a sub-resource: every value comes from the payload
      # the search already returned.
      module Serializer
        protected

        def serialize(contact)
          attrs = contact.is_a?(Hash) ? contact : {}

          native(attrs)
            .merge(account_of(attrs['companies']))
            .merge(location_of(attrs['location']))
            .merge(attribute_values(attrs['custom_attributes']))
        end

        private

        def native(attrs)
          identity(attrs).merge(dates_of(attrs)).merge(flags(attrs)).merge(device_of(attrs))
        end

        def identity(attrs)
          {
            'id' => stringify_id(attrs['id']),
            'role' => attrs['role'],
            'name' => attrs['name'],
            'email' => attrs['email'],
            # Derived rather than read, and filterable all the same: the search
            # endpoint carries a field of its own for it, which is what turns
            # "everyone at this customer" into a filter instead of a wildcard.
            'email_domain' => domain_of(attrs['email']),
            'phone' => attrs['phone'],
            'external_id' => attrs['external_id'],
            'avatar' => attrs['avatar'],
            'owner_id' => stringify_id(attrs['owner_id']),
            'session_count' => attrs['session_count']
          }
        end

        def dates_of(attrs)
          {
            'created_at' => stamp(attrs['created_at']),
            'updated_at' => stamp(attrs['updated_at']),
            'signed_up_at' => stamp(attrs['signed_up_at']),
            'last_seen_at' => stamp(attrs['last_seen_at']),
            'last_contacted_at' => stamp(attrs['last_contacted_at']),
            'last_replied_at' => stamp(attrs['last_replied_at']),
            'last_email_opened_at' => stamp(attrs['last_email_opened_at']),
            'last_email_clicked_at' => stamp(attrs['last_email_clicked_at'])
          }
        end

        def flags(attrs)
          {
            'unsubscribed_from_emails' => attrs['unsubscribed_from_emails'],
            'has_hard_bounced' => attrs['has_hard_bounced'],
            'marked_email_as_spam' => attrs['marked_email_as_spam']
          }
        end

        def device_of(attrs)
          {
            'language_override' => attrs['language_override'],
            'browser' => attrs['browser'],
            'browser_language' => attrs['browser_language'],
            'os' => attrs['os']
          }
        end

        # A contact belongs to several accounts, and the row names the first of
        # them and counts them -- the same reading a conversation gives its
        # contacts. The whole list is a hop away, on the `company` relation.
        def account_of(companies)
          list = nested_list(companies, 'data')
          first = list.first.is_a?(Hash) ? list.first : {}

          { 'company_id' => stringify_id(first['id']), 'company_count' => account_count(companies, list) }
        end

        # Intercom caps the accounts it nests on a contact and says how many
        # there really are, so the count is read rather than measured on the
        # list -- a contact belonging to twelve accounts must not read as
        # belonging to the ten the payload had room for.
        def account_count(companies, list)
          declared = companies['total_count'] if companies.is_a?(Hash)

          declared.is_a?(Numeric) ? declared : list.size
        end

        def location_of(location)
          attrs = location.is_a?(Hash) ? location : {}

          { 'location_country' => attrs['country'], 'location_region' => attrs['region'],
            'location_city' => attrs['city'] }
        end

        def domain_of(email)
          email.to_s[/@(.+)\z/, 1]
        end
      end
    end
  end
end
