module ForestAdminDatasourceIntercom
  module Schema
    # The attributes a workspace defines on its ticket types, read once while the
    # datasource is being constructed.
    #
    # They are declared **per ticket type**, so a single Tickets collection can
    # only carry their union -- and that union is for display. Measured on a real
    # workspace: two types share the names `_default_title_` and
    # `_default_description_` while carrying different attribute ids (14162161
    # against 14162165), and Intercom filters an attribute by id
    # (`ticket_attribute.{id}`), never by name. A union column therefore has no
    # single id to translate to unless the type of the row is known, which is why
    # these ship unfilterable and why filtering on one means a collection per
    # ticket type (R7).
    #
    # The ids are kept per type all the same: they are exactly what the filter
    # translation of the next lot will need, and reading them again would cost a
    # second boot-time round trip.
    class TicketAttributesIntrospector
      # Intercom's attribute data types, mapped onto what Forest can render. A
      # `list` is a single choice among values the workspace defined, so it reads
      # as a string rather than as a Json blob; `files` is a list of attachments
      # and has no scalar form at all.
      COLUMN_TYPES = {
        'string' => 'String', 'list' => 'String', 'integer' => 'Number', 'decimal' => 'Number',
        'boolean' => 'Boolean', 'datetime' => 'Date', 'date' => 'Date', 'files' => 'Json'
      }.freeze

      DEFAULT_COLUMN_TYPE = 'String'.freeze

      # What a column name may not contain, and it has nothing to do with
      # Intercom: Forest lists the fields of a request in a **comma-separated**
      # query parameter, and uses a colon to name a field through a relation.
      # A workspace names its ticket attributes in free text -- measured, one is
      # called `ID de l'objet en question (immo, facture, user)` -- and a comma
      # in there splits the projection into fields no collection has, which the
      # agent rejects as a 400 before the page is ever read.
      UNSAFE_IN_A_COLUMN_NAME = /[,:]/

      # `name` is the key the payload uses, `column_name` the one the schema
      # publishes; they differ whenever the workspace's own name cannot travel
      # through Forest's query string.
      Attribute = Struct.new(:name, :column_name, :column_type, :data_type, :ids_by_ticket_type,
                             keyword_init: true)

      def initialize(client)
        @client = client
      end

      # The union, one entry per attribute name. Degrades to nothing rather than
      # to a failure: a token without the ticket-types permission costs the
      # attribute columns, never the boot of the agent.
      def attributes
        @attributes ||= build
      rescue APIError => e
        ForestAdminDatasourceIntercom.logger.warn(
          "[forest_admin_datasource_intercom] could not read the ticket types (HTTP #{e.status || "-"}); " \
          'the Tickets collection boots without its attribute columns.'
        )
        @attributes = []
      end

      private

      def build
        # Read on the boot connection: this happens while Rails is starting, and
        # a slow Intercom must not turn that into minutes the operator sits
        # through.
        @client.fetch_all('ticket_types', boot: true)
               .each_with_object({}) { |ticket_type, union| collect(ticket_type, union) }
               .values
      end

      def collect(ticket_type, union)
        type_id = ticket_type['id'].to_s
        definitions(ticket_type).each do |definition|
          entry = entry_for(definition, union)
          next if entry.nil?

          entry.ids_by_ticket_type[type_id] = definition['id'].to_s
        end
      end

      # The union is keyed by column name rather than by the workspace's own,
      # since that is what has to be unique in a schema. Two different attributes
      # landing on one column would otherwise share an entry, and the second's
      # values would be read under the first's name -- wrong values rather than
      # missing ones, which is worse.
      def entry_for(definition, union)
        name = definition['name'].to_s
        # An archived attribute is not offered any more, and a nameless one has
        # nothing to be a column of.
        return nil if name.empty? || definition['archived']

        column = column_name_for(name)
        return nil if column.empty?

        entry = union[column]
        return union[column] = attribute_from(name, column, definition) if entry.nil?
        return entry if entry.name == name

        warn_collision(name, entry.name, column)
        nil
      end

      def attribute_from(name, column, definition)
        Attribute.new(name: name, column_name: column, column_type: column_type_for(definition),
                      data_type: definition['data_type'], ids_by_ticket_type: {})
      end

      # Intercom hands these back HTML-escaped -- `Ce que j&#39;ai vérifié` --
      # which is an artefact of where they were typed, not part of the name.
      def column_name_for(name)
        CGI.unescapeHTML(name).gsub(UNSAFE_IN_A_COLUMN_NAME, ' ').squeeze(' ').strip
      end

      def warn_collision(name, kept, column)
        ForestAdminDatasourceIntercom.logger.warn(
          "[forest_admin_datasource_intercom] the ticket attribute #{name.inspect} is left out: it reads as the " \
          "column #{column.inspect}, which #{kept.inspect} already carries. Rename one of them in Intercom to " \
          'publish both.'
        )
      end

      def definitions(ticket_type)
        return [] unless ticket_type.is_a?(Hash)

        container = ticket_type['ticket_type_attributes']
        return [] unless container.is_a?(Hash)

        list = container['data']
        list.is_a?(Array) ? list : []
      end

      # An unknown data type reads as a string rather than being dropped: showing
      # the value Intercom sent beats hiding a column because its type is new.
      def column_type_for(definition)
        COLUMN_TYPES.fetch(definition['data_type'].to_s, DEFAULT_COLUMN_TYPE)
      end
    end
  end
end
