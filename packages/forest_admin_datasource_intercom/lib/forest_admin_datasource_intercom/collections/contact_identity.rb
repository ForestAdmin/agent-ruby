module ForestAdminDatasourceIntercom
  module Collections
    # The contact of a conversation or of a ticket, denormalized onto the row.
    #
    # Intercom nests only the ids -- `{"type": "contact.list", "contacts":
    # [{"id": "..."}]}` -- so a name and an e-mail cost a read. That read is done
    # once per page, for every row at once, and never per row: a page of 25 rows
    # is one request, not 25.
    #
    # It stays a pair of columns rather than a relation because the Contacts
    # collection arrives in lot 4, and a relation whose target collection is
    # missing is a schema the agent refuses to boot on.
    module ContactIdentity
      COLUMNS = %w[contact_name contact_email].freeze

      # How many ids one `id in [...]` read carries. A page holds fewer than this
      # in practice; the chunk keeps the request bounded if it ever does not.
      CONTACT_CHUNK = 100

      private

      def define_contact_columns
        add_column('contact_ids', 'Json')
        add_column('contact_count', 'Number')
        add_column('contact_name', 'String')
        add_column('contact_email', 'String')
      end

      # A group conversation, or a ticket opened for several people, has more
      # than one contact: the row names the first and counts them, rather than
      # presenting one of several as the one.
      def contact_columns_for(attrs)
        ids = nested_list(attrs['contacts'], 'contacts').filter_map { |contact| stringify_id(contact['id']) }

        { 'contact_ids' => ids, 'contact_count' => ids.size,
          # Filled by the bulk read below, and left nil when the projection did
          # not ask for them.
          'contact_name' => nil, 'contact_email' => nil }
      end

      def first_contact_id(record)
        contact = nested_list((record || {})['contacts'], 'contacts').first
        contact.is_a?(Hash) ? stringify_id(contact['id']) : nil
      end

      def embed_contact_identity(records, rows, projection)
        return unless (COLUMNS & projection).any?

        identities = contact_identities(records)
        records.each_with_index do |record, index|
          identity = identities[first_contact_id(record)] || {}
          rows[index]['contact_name'] = identity['name'] if rows[index].key?('contact_name')
          rows[index]['contact_email'] = identity['email'] if rows[index].key?('contact_email')
        end
      end

      # A failure costs the two columns and nothing else: an identity that could
      # not be read is not a page that could not be served.
      def contact_identities(records)
        ids = records.filter_map { |record| first_contact_id(record) }.uniq
        return {} if ids.empty?

        ids.each_slice(CONTACT_CHUNK).with_object({}) do |chunk, indexed|
          page = client.search_page('contacts/search', per_page: chunk.size,
                                                       query: { 'field' => 'id', 'operator' => 'IN',
                                                                'value' => chunk })
          page.records.each { |contact| indexed[contact['id'].to_s] = contact }
        end
      rescue APIError => e
        ForestAdminDatasourceIntercom.logger.warn(
          "[forest_admin_datasource_intercom] #{name} could not read the contacts of this page (HTTP " \
          "#{e.status || "-"}); the name and e-mail columns are left empty for it."
        )
        {}
      end
    end
  end
end
