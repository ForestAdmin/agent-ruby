module ForestAdminDatasourcePylon
  module Collections
    class Account < CursorCollection
      include SchemaDefinition
      include Serializer

      def initialize(datasource, custom_fields: [])
        super(datasource, 'PylonAccount', custom_fields: custom_fields, searchable: true)
      end

      protected

      def filter_table = ApiFilters

      def unsortable_warning
        '[forest_admin_datasource_pylon] PylonAccount cannot honour the requested order; neither GET /accounts ' \
          'nor POST /accounts/search takes a sort parameter, so accounts come back in the order the API imposes.'
      end

      def search_page(limit:, cursor:, filter:, search_text:)
        datasource.client.search_accounts(limit: limit, cursor: cursor, filter: filter, search_text: search_text)
      end

      def list_page(limit:, cursor:)
        datasource.client.list_accounts(limit: limit, cursor: cursor)
      end

      def fetch_one(id)
        datasource.client.fetch_account(id)
      end
    end
  end
end
