module ForestAdminDatasourceIntercom
  module Query
    # Reads `search_fields.yml`, the table of what Intercom's search endpoints
    # filter, and hands it to the schema and to the translator as objects rather
    # than as nested hashes.
    #
    # The table is data rather than code for one reason: `bin/probe_search_fields`
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
      Field = Struct.new(:column, :field, :type, :operators, :source, keyword_init: true) do
        def measured? = source == 'measured'
      end

      # A column that stays unfilterable, and why. The reason travels into the
      # refusal the operator reads, so it names what to filter on instead
      # wherever there is something to name.
      Refusal = Struct.new(:column, :reason, :source, keyword_init: true) do
        def measured? = source == 'measured'
      end

      Endpoint = Struct.new(:name, :path, :measured_at, :fields, :refused, :candidates, :ticket_attributes,
                            keyword_init: true) do
        # Whether the probe has run against a real workspace for this endpoint.
        # False means every `spec` row is still a candidate.
        def measured? = !measured_at.nil?

        def field(column) = fields[column]
        def refusal(column) = refused[column]
        def filterable_columns = fields.keys
        def unmeasured_fields = fields.values.reject(&:measured?)
      end

      class << self
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
          Endpoint.new(
            name: name,
            path: definition.fetch('path'),
            measured_at: definition['measured_at'],
            fields: fields(name, definition['fields']),
            refused: refusals(name, definition['refused']),
            candidates: Array(definition['candidates']).freeze,
            ticket_attributes: definition['ticket_attributes']
          ).freeze
        end

        def fields(endpoint, declared)
          (declared || {}).to_h do |column, row|
            field = Field.new(column: column, field: row.fetch('field'), type: row.fetch('type'),
                              operators: Array(row['operators']).freeze, source: row.fetch('source')).freeze
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
