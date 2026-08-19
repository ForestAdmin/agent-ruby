module ForestAdminDatasourcePylon
  module Collections
    class Contact < CursorCollection
      include SchemaDefinition
      include Serializer

      # `POST /contacts` takes the primary address alone; the other ones are set
      # on an existing contact.
      UPDATE_ONLY = %w[emails].freeze

      def initialize(datasource, custom_fields: [])
        super(datasource, 'PylonContact', custom_fields: custom_fields, searchable: true)
      end

      protected

      def filter_table = ApiFilters

      def create_record(payload) = datasource.client.create_contact(payload)
      def update_record(id, payload) = datasource.client.update_contact(id, payload)
      def delete_record(id) = datasource.client.delete_contact(id)

      def update_only_fields = UPDATE_ONLY

      def unsortable_warning
        '[forest_admin_datasource_pylon] PylonContact cannot honour the requested order; neither GET /contacts ' \
          'nor POST /contacts/search takes a sort parameter, so contacts come back in the order the API imposes.'
      end

      def search_page(limit:, cursor:, filter:, search_text:)
        datasource.client.search_contacts(limit: limit, cursor: cursor, filter: filter, search_text: search_text)
      end

      def list_page(limit:, cursor:)
        datasource.client.list_contacts(limit: limit, cursor: cursor)
      end

      def fetch_one(id)
        datasource.client.fetch_contact(id)
      end
    end
  end
end
