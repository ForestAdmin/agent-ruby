module ForestAdminDatasourcePylon
  module Schema
    # Turns the custom fields an organization defined in Pylon into columns, as
    # entries shaped `{ column_name:, schema: }` — what `add_custom_fields`
    # registers on a collection.
    #
    # `column_name` is the Pylon slug verbatim, and there is no second key
    # carrying it: the slug is both what a read payload indexes the values by and
    # what a search filter sends as `field`, so renaming the column would add a
    # mapping to keep in step for nothing.
    #
    # Pylon defines custom fields per object type, and asks for that type on
    # every call: `issue`, `account` and `contact` are the three this datasource
    # has a collection for — it also exposes `task`, `project`, `meeting` and
    # `opportunity`, while users and teams carry no custom field at all.
    class CustomFieldsIntrospector
      ColumnSchema = ForestAdminDatasourceToolkit::Schema::ColumnSchema
      Maps         = Query::OperatorMaps

      # A type absent from this table is skipped rather than guessed at: a column
      # whose Forest type does not match what Pylon holds would filter and
      # display wrong, which is worse than not being there.
      #
      # `user` holds a Pylon user id, kept a String rather than turned into a
      # relation to PylonUser: a custom field is registered after the relations
      # are declared, and a foreign key the operator can read is what this story
      # promises.
      PYLON_TO_COLUMN_TYPE = {
        'text' => 'String',
        'url' => 'String',
        'user' => 'String',
        'number' => 'Number',
        'decimal' => 'Number',
        'boolean' => 'Boolean',
        'date' => 'Dateonly',
        'datetime' => 'Date',
        'select' => 'Enum',
        'multiselect' => 'Json'
      }.freeze

      BASE_OPS = (Maps::EQUALITY.keys + Maps::PRESENCE.keys).freeze
      TIME_OPS = (BASE_OPS + Maps::TIME.keys).freeze

      # Drawn from `CUSTOM_FIELD_OPS`, the set every search endpoint accepts on a
      # custom field, so a collection's clamp has nothing to drop.
      #
      # A Number gets no comparison: Pylon documents `time_is_after` /
      # `time_is_before` for the bare comparisons and nothing else, so a numeric
      # range would travel as a time filter. A multiselect gets nothing at all —
      # its membership operators are not part of what a custom field accepts.
      OPERATORS = {
        'String' => (BASE_OPS + Maps::FULL_TEXT.keys).freeze,
        'Enum' => BASE_OPS,
        'Number' => BASE_OPS,
        'Boolean' => BASE_OPS,
        'Date' => TIME_OPS,
        'Dateonly' => TIME_OPS,
        'Json' => [].freeze
      }.freeze

      def initialize(client)
        @client = client
      end

      def issue_custom_fields   = introspect('issue')
      def account_custom_fields = introspect('account')
      def contact_custom_fields = introspect('contact')

      private

      def introspect(object_type)
        Array(@client.fetch_custom_fields(object_type)).filter_map { |raw| build_entry(raw, object_type) }
      end

      def build_entry(raw, object_type)
        return nil unless raw.is_a?(Hash)

        slug = raw['slug'].to_s
        return nil if slug.empty?

        column_type = PYLON_TO_COLUMN_TYPE[raw['type']]
        return warn_unknown_type(raw, slug, object_type) if column_type.nil?

        { column_name: slug, schema: build_schema(raw, column_type) }
      end

      # Every custom field is read-only in this story, like every native column:
      # writes land in story 7 (EXT-11), which is also where Pylon's own
      # `is_read_only` flag starts being honoured. Nothing is sortable either --
      # no Pylon endpoint takes a sort parameter.
      def build_schema(raw, column_type)
        opts = { column_type: column_type,
                 filter_operators: OPERATORS.fetch(column_type, []),
                 is_read_only: true,
                 is_sortable: false }

        column_type == 'Enum' ? enum_schema(raw, opts) : ColumnSchema.new(**opts)
      end

      # Pylon reads a select back — and filters it — as the slug of the option,
      # never as its label, so those are the values the column advertises.
      #
      # Forest refuses an Enum carrying no value: a select whose options were all
      # removed falls back to String, so the column still shows what it holds.
      def enum_schema(raw, opts)
        values = option_slugs(raw)
        return ColumnSchema.new(**opts, enum_values: values) unless values.empty?

        ColumnSchema.new(**opts, column_type: 'String', filter_operators: OPERATORS.fetch('String'))
      end

      def option_slugs(raw)
        metadata = raw['select_metadata']
        options  = metadata.is_a?(Hash) ? metadata['options'] : nil

        Array(options).filter_map do |option|
          option['slug'] if option.is_a?(Hash) && !option['slug'].to_s.empty?
        end
      end

      def warn_unknown_type(raw, slug, object_type)
        ForestAdminDatasourcePylon.logger.warn(
          "[forest_admin_datasource_pylon] Custom field '#{slug}' on #{object_type} has type " \
          "#{raw["type"].inspect}, which this datasource cannot map to a Forest column; skipping."
        )
        nil
      end
    end
  end
end
