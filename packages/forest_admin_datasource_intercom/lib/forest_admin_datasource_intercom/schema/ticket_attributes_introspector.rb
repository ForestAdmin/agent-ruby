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

      Attribute = Struct.new(:name, :column_type, :data_type, :ids_by_ticket_type, keyword_init: true)

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
          name = definition['name'].to_s
          # An archived attribute is not offered any more, and a nameless one has
          # nothing to be a column of.
          next if name.empty? || definition['archived']

          entry = union[name] ||= Attribute.new(name: name, column_type: column_type_for(definition),
                                                data_type: definition['data_type'], ids_by_ticket_type: {})
          entry.ids_by_ticket_type[type_id] = definition['id'].to_s
        end
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
