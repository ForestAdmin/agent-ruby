module ForestAdminDatasourcePylon
  module Schema
    # Turns the custom fields an organization defined in Pylon into columns, as
    # entries shaped `{ column_name:, schema:, multi_value: }` — what
    # `add_custom_fields` registers on a collection, and what the payload
    # builder writes a value back through.
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

      # The types Pylon writes back through `values` rather than `value`.
      MULTI_VALUE_TYPES = %w[multiselect].freeze

      BASE_OPS = (Maps::EQUALITY.keys + Maps::PRESENCE.keys).freeze

      # A date drops the membership operators on the way, `Rules` granting a DATE
      # or a DATEONLY column no array operator -- the hazard already documented
      # for MEMBERSHIP in `operator_maps.rb`. Native date columns declare the
      # comparisons alone for the same reason.
      #
      # Dropping them is not what keeps `in` out of the UI, though, and nothing
      # here can: `OperatorsEquivalenceCollectionDecorator` republishes it from
      # the `equal` this set declares, the IN transform depending on EQUAL for
      # every column type. A DATEONLY also gets `after_x_hours_ago` /
      # `before_x_hours_ago` republished from the comparisons, `Times.compare`
      # deriving them for that type where `Rules` refuses them. The validator
      # then rejects all three, so the operator is offered a date filter the
      # agent answers with a 400. The contradiction is the toolkit's to settle
      # and is tracked as PRD-989; the set below is what Pylon accepts, which is
      # the only question this table can answer.
      TIME_OPS = (BASE_OPS - Maps::MEMBERSHIP.keys + Maps::TIME.keys).freeze

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
        @unreachable = false
      end

      def issue_custom_fields   = introspect('issue')
      def account_custom_fields = introspect('account')
      def contact_custom_fields = introspect('contact')

      private

      # One object type per call, three of them, all of it in front of a Rails
      # boot the operator sits through. The first failure stands for the rest:
      # a Pylon that is down, or a token missing the permission, fails the two
      # that follow the same way, and each is bounded per request rather than
      # across the three — so trying them anyway spends the bound three times to
      # learn what the first one already said.
      def introspect(object_type)
        return [] if @unreachable

        definitions = @client.fetch_custom_fields(object_type)
        return give_up(object_type) if definitions.nil?

        definitions.filter_map { |raw| build_entry(raw, object_type) }
      end

      def give_up(object_type)
        @unreachable = true
        ForestAdminDatasourcePylon.logger.warn(
          "[forest_admin_datasource_pylon] Custom fields could not be read for #{object_type}; " \
          'the object types after it are left unread rather than held against the same failure. ' \
          'The datasource boots on the native schema, without the custom columns.'
        )
        []
      end

      def build_entry(raw, object_type)
        return nil unless raw.is_a?(Hash)

        slug = raw['slug'].to_s
        return nil if slug.empty?

        column_type = PYLON_TO_COLUMN_TYPE[raw['type']]
        return warn_unknown_type(raw, slug, object_type) if column_type.nil?

        { column_name: slug, schema: build_schema(raw, column_type),
          multi_value: MULTI_VALUE_TYPES.include?(raw['type']) }
      end

      # A custom field is writable when Pylon says it is: it flags the ones
      # synced from an app or an integration, which its own endpoints refuse.
      # Nothing is sortable -- no Pylon endpoint takes a sort parameter -- and
      # nothing is groupable: one column left groupable turns `supportGroups` on
      # for the whole collection, and the group-by the UI then offers errors.
      def build_schema(raw, column_type)
        opts = { column_type: column_type,
                 filter_operators: OPERATORS.fetch(column_type, []),
                 is_read_only: !writable_definition?(raw),
                 is_sortable: false,
                 is_groupable: false }

        column_type == 'Enum' ? enum_schema(raw, opts) : ColumnSchema.new(**opts)
      end

      # Pylon reads a select back — and filters it — as the slug of the option,
      # never as its label, so those are the values the column advertises.
      #
      # Forest refuses an Enum carrying no value: a select whose options were all
      # removed falls back to String, so the column still shows what it holds.
      #
      # Read-only there whatever Pylon says of the field, unlike every other
      # fallback here: a select is written as the slug of one of its options, so
      # a free-text editor on one offers the operator no value the endpoint would
      # accept. Showing what it holds is the whole of what this can do.
      def enum_schema(raw, opts)
        values = option_slugs(raw)
        return ColumnSchema.new(**opts, enum_values: values) unless values.empty?

        ColumnSchema.new(**opts, column_type: 'String',
                                 filter_operators: OPERATORS.fetch('String'), is_read_only: true)
      end

      def option_slugs(raw)
        metadata = raw['select_metadata']
        options  = metadata.is_a?(Hash) ? metadata['options'] : nil

        Array(options).filter_map do |option|
          option['slug'] if option.is_a?(Hash) && !option['slug'].to_s.empty?
        end
      end

      # Only an explicit `false` opens a custom field to writes. A definition
      # carrying no flag at all is left read-only and reported: this datasource
      # advertises nothing an endpoint would refuse, and reading the absence as
      # "writable" would turn every field synced from an app into an editor whose
      # every save Pylon rejects -- where reading it as "read-only" costs the
      # capability and says so once per boot.
      def writable_definition?(raw)
        return true if raw['is_read_only'] == false
        return false if raw['is_read_only'] == true

        warn_unflagged_writability(raw)
        false
      end

      def warn_unflagged_writability(raw)
        ForestAdminDatasourcePylon.logger.warn(
          "[forest_admin_datasource_pylon] Custom field '#{raw["slug"]}' carries no 'is_read_only' flag; " \
          'leaving it read-only. Pylon refuses a write on the fields it syncs from an app or an integration, ' \
          'and nothing here can tell this one apart from those without the flag.'
        )
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
