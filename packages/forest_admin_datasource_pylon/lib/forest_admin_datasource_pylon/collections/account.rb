module ForestAdminDatasourcePylon
  module Collections
    class Account < CursorCollection
      include SchemaDefinition
      include Serializer

      # Pylon reads an account's type back as `type` and takes it as
      # `account_type`.
      RENAMES = { 'type' => 'account_type' }.freeze

      # An account is created enabled; only `PATCH /accounts/{id}` disables one.
      UPDATE_ONLY = %w[is_disabled].freeze

      def initialize(datasource, custom_fields: [])
        super(datasource, 'PylonAccount', custom_fields: custom_fields, searchable: true)
      end

      protected

      def filter_table = ApiFilters

      def create_record(payload) = datasource.client.create_account(payload)
      def update_record(id, payload) = datasource.client.update_account(id, payload)
      def delete_record(id) = datasource.client.delete_account(id)

      def update_only_fields = UPDATE_ONLY
      def payload_renames = RENAMES

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
