module ForestAdminDatasourceIntercom
  module Query
    # Reads `search_fields.yml`, the table of what Intercom's search endpoints
    # filter, and hands it to the schema and to the translator as objects rather
    # than as nested hashes.
    #
    # The table is data rather than code for one reason: `forest_admin_intercom_probe`
    # rewrites it from a real workspace. Anything derived from it -- which
    # columns are filterable, with which Forest operators, and what an operator
    # is told about the ones that are not -- therefore follows a measurement
    # instead of a hand-written list that drifts from the endpoint.
    #
    # Every row is validated on load. The file ships with the gem and is written
    # by a script, so a typo in an operator, or a column filed as both filterable
    # and refused, is a defect of this package: it fails at boot rather than
    # producing a schema nobody can explain.
    module SearchFields
      PATH = File.expand_path('search_fields.yml', __dir__)

      # The operators Intercom's search DSL spells, and nothing else: `=`, `!=`,
      # `>`, `<`, `>=`, `<=`, the substring pair `~` / `!~`, the anchors `^` /
      # `$`, and the membership pair. Which of them an endpoint honours on a
      # given field is the table's business; this is only the alphabet.
      KNOWN_OPERATORS = ['=', '!=', '>', '<', '>=', '<=', '~', '!~', '^', '$', 'IN', 'NIN'].freeze
      # Read off the operator table rather than listed again here: a type with
      # no spelling of its own would pass this validation and raise when the
      # schema asked what to publish on it.
      KNOWN_TYPES = OperatorTable.types
      KNOWN_SOURCES = %w[measured spec].freeze

      # `source` says where a row comes from, and `measured?` is what the boot
      # report and the README section read: a row taken from the documentation is
      # a candidate the probe has not confirmed.
      # `sortable` is the one thing here Intercom answers on a single endpoint:
      # `/contacts/search` takes a `sort`, the other two take one and ignore it
      # without a word. Absent reads as false, so a table saying nothing leaves
      # a column unsortable rather than promising an order.
      Field = Struct.new(:column, :field, :type, :operators, :source, :sortable, keyword_init: true) do
        def measured? = source == 'measured'
        def sortable? = sortable == true
      end

      # A column that stays unfilterable, and why. The reason travels into the
      # refusal the operator reads, so it names what to filter on instead
      # wherever there is something to name.
      Refusal = Struct.new(:column, :reason, :source, keyword_init: true) do
        def measured? = source == 'measured'
      end

      Endpoint = Struct.new(:name, :path, :measured_at, :fields, :refused, :candidates, :attribute_refusal,
                            keyword_init: true) do
        # Whether the probe has run against a real workspace for this endpoint.
        # False means every `spec` row is still a candidate.
        def measured? = !measured_at.nil?

        def field(column) = fields[column]
        def refusal(column) = refused[column]
        def filterable_columns = fields.keys
        def sortable_columns = fields.values.select(&:sortable?).map(&:column)
        def unmeasured_fields = fields.values.reject(&:measured?)
      end

      # Long by line count only: it is one parse method and one validation per
      # thing the file can get wrong, and a validation that does not say what
      # is wrong is one nobody can act on.
      class << self # rubocop:disable Metrics/ClassLength
        def fetch(name)
          table[name.to_s] ||
            raise(ConfigurationError, "Unknown Intercom search endpoint #{name.inspect}; " \
                                      "the table declares #{table.keys.join(", ")}.")
        end

        def endpoints = table.keys

        def table
          @table ||= build(YAML.safe_load_file(PATH))
        end

        # Public so a spec can feed it a table of its own: this validation is the
        # reason the file can be rewritten by a script without the package
        # trusting whatever comes back.
        def build(raw)
          raw.fetch('endpoints').to_h { |name, definition| [name, endpoint(name, definition)] }.freeze
        end

        private

        def endpoint(name, definition)
          filterable = fields(name, definition['fields'])
          refused = refusals(name, definition['refused'])
          validate_no_overlap!(name, filterable, refused)

          Endpoint.new(
            name: name,
            path: definition.fetch('path'),
            measured_at: definition['measured_at'],
            fields: filterable,
            refused: refused,
            candidates: Array(definition['candidates']).freeze,
            attribute_refusal: attribute_refusal(name, definition)
          ).freeze
        end

        # The refusal that covers a whole family of columns rather than one:
        # the attributes a workspace defines, whose names are unknown until the
        # datasource boots and which therefore cannot have a row each. Spelled
        # `ticket_attributes` on the endpoint that carries them per ticket type
        # and `custom_attributes` on the ones that carry them per model, since
        # that is the workspace's own vocabulary and what an operator goes and
        # renames.
        #
        # Read by the translator, which is the point: without it a filter on
        # such a column falls back on the generic "takes no filter on it",
        # where this says why -- and the reason is the arbitration, not an
        # oversight.
        def attribute_refusal(endpoint, definition)
          column = %w[ticket_attributes custom_attributes].find { |key| definition.key?(key) }
          return nil if column.nil?

          row = definition.fetch(column)
          refusal = Refusal.new(column: column, reason: squish(row.fetch('reason')), source: row.fetch('source'))
          validate_source!(endpoint, column, refusal)
          validate_attributes_unfilterable!(endpoint, column, row)

          refusal.freeze
        end

        # `filterable: true` is a state nothing here implements: the whole
        # block is a refusal, and a rewrite flipping the flag would publish
        # nothing new while making the file say the opposite of what it does.
        def validate_attributes_unfilterable!(endpoint, column, row)
          return if row.fetch('filterable') == false

          malformed!(endpoint, column,
                     "filterable #{row["filterable"].inspect} is not something this reads; the attribute columns " \
                     'are published for display only, and the block exists to say why')
        end

        # A column filed as both filterable and refused. `Endpoint#field` is
        # consulted first, so the filterable row would win and the refusal --
        # with the reason an operator reads -- would be ignored in silence. The
        # file is rewritten by a script, so this is the shape a bad rewrite
        # takes, and it fails at load rather than producing a schema nobody can
        # explain.
        def validate_no_overlap!(endpoint, filterable, refused)
          both = filterable.keys & refused.keys
          return if both.empty?

          malformed!(endpoint, both.join(', '),
                     'it is declared filterable and refused at once; the refusal would be ignored')
        end

        def fields(endpoint, declared)
          (declared || {}).to_h do |column, row|
            field = Field.new(column: column, field: row.fetch('field'), type: row.fetch('type'),
                              operators: Array(row['operators']).freeze, source: row.fetch('source'),
                              sortable: row.fetch('sortable', false)).freeze
            validate_field!(endpoint, field)

            [column, field]
          end.freeze
        end

        def refusals(endpoint, declared)
          (declared || {}).to_h do |column, row|
            refusal = Refusal.new(column: column, reason: squish(row.fetch('reason')),
                                  source: row.fetch('source')).freeze
            validate_source!(endpoint, column, refusal)

            [column, refusal]
          end.freeze
        end

        def validate_field!(endpoint, field)
          validate_source!(endpoint, field.column, field)
          validate_type!(endpoint, field)
          validate_operators!(endpoint, field)
          validate_publishable!(endpoint, field)
          validate_sortable!(endpoint, field)
        end

        # Operators the DSL spells, none of which this column's *type* can carry:
        # a `date` row declaring `~` passes the alphabet above and publishes
        # nothing, `OperatorTable` mapping no Forest operator onto it. The result
        # is a column the table calls filterable that no filter can reach, and
        # the translator refusing every request on it -- the same
        # advertise-then-refuse this package exists to prevent, one layer lower.
        def validate_publishable!(endpoint, field)
          return unless OperatorTable.forest_operators(field).empty?

          malformed!(endpoint, field.column,
                     "none of #{field.operators.join(", ")} is an operator Intercom answers on a " \
                     "#{field.type}, so the column would publish no filter at all")
        end

        # Anything but a boolean, `"true"` above all: YAML reads it as a string,
        # which is truthy in Ruby and would publish a sortable column out of a
        # typo the file cannot otherwise show.
        def validate_sortable!(endpoint, field)
          return if [true, false].include?(field.sortable)

          malformed!(endpoint, field.column, "sortable #{field.sortable.inspect} is neither true nor false")
        end

        def validate_type!(endpoint, field)
          return if KNOWN_TYPES.include?(field.type)

          malformed!(endpoint, field.column, "type #{field.type.inspect} is not one of #{KNOWN_TYPES.join(", ")}")
        end

        # An empty operator list is how a table stops short of saying anything:
        # it would publish a filterable column no operator can reach. A column
        # Intercom does not filter belongs in the refused table, where it comes
        # with the reason an operator reads.
        def validate_operators!(endpoint, field)
          if field.operators.empty?
            malformed!(endpoint, field.column,
                       'it declares no operator; a column Intercom cannot filter belongs in the refused table')
          end

          unknown = field.operators - KNOWN_OPERATORS
          return if unknown.empty?

          malformed!(endpoint, field.column, "Intercom's search DSL has no operator #{unknown.join(", ")}")
        end

        def validate_source!(endpoint, column, row)
          return if KNOWN_SOURCES.include?(row.source)

          malformed!(endpoint, column, "source #{row.source.inspect} is neither #{KNOWN_SOURCES.join(" nor ")}")
        end

        def malformed!(endpoint, column, detail)
          raise ConfigurationError, "#{File.basename(PATH)} is malformed at #{endpoint}.#{column}: #{detail}."
        end

        # A YAML folded block keeps the newlines the file needs to stay readable;
        # the reason travels into a one-line message.
        def squish(text) = text.to_s.split.join(' ')
      end
    end
  end
end
