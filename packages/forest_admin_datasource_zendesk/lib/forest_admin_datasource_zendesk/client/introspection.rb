module ForestAdminDatasourceZendesk
  class Client
    module Introspection
      def fetch_ticket_fields
        best_effort('fetch_ticket_fields (custom fields will be unavailable)', default: []) do
          Array(api.connection.get('ticket_fields').body['ticket_fields'])
        end
      end

      def fetch_user_fields
        best_effort('fetch_user_fields (custom fields will be unavailable)', default: []) do
          Array(api.connection.get('user_fields').body['user_fields'])
        end
      end

      def fetch_organization_fields
        best_effort('fetch_organization_fields (custom fields will be unavailable)', default: []) do
          Array(api.connection.get('organization_fields').body['organization_fields'])
        end
      end
    end
  end
end
