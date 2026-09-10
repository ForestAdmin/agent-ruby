module ForestAdminDatasourceIntercom
  module Collections
    # The contact of a conversation or of a ticket, on the row itself.
    #
    # Intercom nests only the ids -- `{"type": "contact.list", "contacts":
    # [{"id": "..."}]}` -- so a name costs a read. That read is done once per
    # page, for every row at once, and never per row: a page of 25 rows is one
    # request, not 25.
    #
    # **Three columns, where lot 1 published four.** Now that the Contacts
    # collection exists, the identity is a relation, and the rule lot 2.5 set
    # for the ticket labels applies here too: one readable label on the row plus
    # the relation to navigate, rather than two ways to read one fact.
    # `contact_email` is gone -- it is one hop away, on `contact:email` -- and
    # `contact_ids` gave way to `contact_id`, which is a foreign key rather than
    # a Json blob no filter could reach. The list of every contact of a group
    # conversation is the `contacts` relation.
    module ContactIdentity
      COLUMNS = %w[contact_name].freeze

      # How many ids one `id in [...]` read carries. A page holds fewer than this
      # in practice; the chunk keeps the request bounded if it ever does not.
      CONTACT_CHUNK = 100

      private

      def define_contact_columns
        add_column('contact_id', 'String')
        add_column('contact_count', 'Number')
        add_column('contact_name', 'String')
      end

      # A group conversation, or a ticket opened for several people, has more
      # than one contact: the row names the first and counts them, rather than
      # presenting one of several as the one. The `contact` relation resolves
      # that same first contact, so the column and the relation cannot disagree;
      # the others are reached through the contact's own conversations.
      def contact_columns_for(attrs)
        ids = nested_list(attrs['contacts'], 'contacts').filter_map { |contact| stringify_id(contact['id']) }

        { 'contact_id' => ids.first, 'contact_count' => ids.size,
          # Filled by the bulk read below, and left nil when the projection did
          # not ask for it.
          'contact_name' => nil }
      end

      def first_contact_id(record)
        contact = nested_list((record || {})['contacts'], 'contacts').first
        contact.is_a?(Hash) ? stringify_id(contact['id']) : nil
      end

      # The Contacts endpoint as the table spells it, rather than a path written
      # a second time here: this is the same `/contacts/search` the Contacts
      # collection reads itself through, and a table that renamed it would
      # otherwise leave this one behind.
      def contact_search_path
        @contact_search_path ||= Query::SearchFields.fetch('contacts').path
      end

      def embed_contact_identity(records, rows, projection)
        return unless any_column_asked?(projection, COLUMNS)

        identities = contact_identities(records)
        records.each_with_index do |record, index|
          identity = identities[first_contact_id(record)] || {}
          rows[index]['contact_name'] = identity['name'] if rows[index].key?('contact_name')
        end
      end

      # A failure costs the column and nothing else: an identity that could not
      # be read is not a page that could not be served.
      def contact_identities(records)
        ids = records.filter_map { |record| first_contact_id(record) }.uniq
        return {} if ids.empty?

        ids.each_slice(CONTACT_CHUNK).with_object({}) do |chunk, indexed|
          page = client.search_page(contact_search_path, per_page: chunk.size,
                                                         query: { 'field' => 'id', 'operator' => 'IN',
                                                                  'value' => chunk })
          page.records.each { |contact| indexed[contact['id'].to_s] = contact }
        end
      rescue APIError => e
        ForestAdminDatasourceIntercom.logger.warn(
          "[forest_admin_datasource_intercom] #{name} could not read the contacts of this page (HTTP " \
          "#{e.status || "-"}); the name column is left empty for it."
        )
        {}
      end
    end
  end
end
