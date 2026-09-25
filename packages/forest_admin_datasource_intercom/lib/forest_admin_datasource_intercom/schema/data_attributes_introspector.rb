module ForestAdminDatasourceIntercom
  module Schema
    # The attributes a workspace defines on its contacts and on its companies,
    # read once while the datasource is being constructed.
    #
    # Unlike a ticket attribute, one of these is declared **per model** rather
    # than per ticket type, so the union is the whole set and a column maps onto
    # exactly one Intercom attribute -- the ambiguity that keeps ticket
    # attributes display-only (R7) does not arise here. What keeps these
    # display-only is narrower and temporary: which operators Intercom answers
    # on `custom_attributes.{name}` has not been measured, and this package
    # publishes no filter it has not seen work.
    #
    # `api_writable` is read and carried although every column of this lot is
    # published read-only. It costs nothing now and it is exactly what lot 4b
    # needs to tell an attribute it may write from one Intercom fills in
    # itself -- re-reading it later would be a second boot-time round trip.
    class DataAttributesIntrospector
      include AttributeNaming

      # Intercom's attribute data types, mapped onto what Forest can render.
      COLUMN_TYPES = {
        'string' => 'String', 'integer' => 'Number', 'float' => 'Number', 'decimal' => 'Number',
        'boolean' => 'Boolean', 'date' => 'Date', 'datetime' => 'Date'
      }.freeze

      DEFAULT_COLUMN_TYPE = 'String'.freeze

      # `name` is the key `custom_attributes` uses, `column_name` the one the
      # schema publishes; they differ whenever the workspace's own name cannot
      # travel through Forest's query string.
      Attribute = Struct.new(:name, :column_name, :column_type, :data_type, :api_writable, keyword_init: true)

      def initialize(client, model:)
        @client = client
        @model = model
      end

      # Degrades to nothing rather than to a failure: a token without the
      # permission on this model costs the custom-attribute columns, never the
      # boot of the agent.
      def attributes
        @attributes ||= build
      rescue APIError => e
        ForestAdminDatasourceIntercom.logger.warn(
          "[forest_admin_datasource_intercom] could not read the #{@model} attributes (HTTP #{e.status || "-"}); " \
          'the collection boots without its custom-attribute columns.'
        )
        @attributes = []
      end

      private

      def build
        # Read on the boot connection: this happens while Rails is starting, and
        # a slow Intercom must not turn that into minutes the operator sits
        # through.
        @client.fetch_all('data_attributes', params: { 'model' => @model }, boot: true)
               .each_with_object({}) { |definition, union| collect(definition, union) }
               .values
      end

      # The standard attributes are left out: they are columns this datasource
      # declares by hand, with the filters the search table measured, and
      # publishing them a second time under their `custom_attributes` name would
      # show one fact twice -- the unfilterable copy winning nothing.
      def collect(definition, union)
        return unless definition.is_a?(Hash) && definition['custom'] && !definition['archived']

        name = definition['name'].to_s
        return if name.empty?

        column = column_name_for(name)
        return if column.empty?

        add(union, name, column, definition)
      end

      def add(union, name, column, definition)
        entry = union[column]
        return union[column] = attribute_from(name, column, definition) if entry.nil?
        return if entry.name == name

        warn_collision(name, entry.name, column)
      end

      def attribute_from(name, column, definition)
        Attribute.new(name: name, column_name: column, column_type: column_type_for(definition),
                      data_type: definition['data_type'], api_writable: definition['api_writable'] == true)
      end

      # These are declared per model, so that is what the log calls them: it is
      # the workspace's own vocabulary, and where the operator goes to rename
      # the one that was left out.
      def attribute_kind = @model
    end
  end
end
