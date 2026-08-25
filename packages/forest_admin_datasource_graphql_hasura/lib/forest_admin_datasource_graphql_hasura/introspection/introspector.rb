require 'active_support/core_ext/string/inflections'

module ForestAdminDatasourceGraphqlHasura
  module Introspection
    # Builds the datasource structure from the GraphQL introspection query
    # (tables, columns, relationship fields) and the Hasura metadata API
    # (relationship column mappings), when the latter is reachable.
    class Introspector
      INTROSPECTION_QUERY = <<~GRAPHQL.freeze
        query IntrospectSchema {
          __schema {
            types {
              name
              kind
              fields {
                name
                type { ...TypeRef }
              }
              enumValues { name }
            }
            queryType {
              name
              fields {
                name
                type { ...TypeRef }
                args {
                  name
                  type { name kind ofType { name kind } }
                }
              }
            }
          }
        }
        fragment TypeRef on __Type {
          name
          kind
          ofType {
            name
            kind
            ofType {
              name
              kind
              ofType { name kind }
            }
          }
        }
      GRAPHQL

      SCALAR_TYPES = %w[
        Int Float String Boolean ID
        uuid timestamptz timestamp date time timetz jsonb json numeric bigint smallint
        integer real double_precision text varchar char bpchar bytea inet cidr macaddr
        money interval bit xml citext
        _text _int4 _uuid _jsonb
      ].to_set.freeze

      # A Postgres enum, or any scalar Hasura exposes under a custom name
      # (`macaddr`, a domain type…), displays as a string but has no
      # `_like`/`_ilike` in its comparison expression.
      TEXT_TYPES = %w[String ID text varchar char bpchar citext bytea].to_set.freeze

      EXCLUDED_PREFIXES = %w[__ hdb_ pg_ information_schema].freeze

      def initialize(client, configuration)
        @client = client
        @configuration = configuration
      end

      # @return [Array<Table>]
      def introspect
        types, query_fields = introspection_payload
        metadata = @client.fetch_metadata

        @type_map = build_type_map(types)
        @custom_root_fields = {}
        @relationship_mappings = metadata ? safe_relationship_mappings(metadata) : {}
        @primary_keys = parse_primary_keys(query_fields)

        parse_tables(query_fields)
      end

      private

      # A gateway can answer 200 with `__schema: null` or partial objects when
      # introspection is disabled: better a named error than a NoMethodError.
      def introspection_payload
        response = @client.execute(INTROSPECTION_QUERY)
        schema = response.is_a?(Hash) ? response['__schema'] : nil
        types = schema.is_a?(Hash) ? schema['types'] : nil
        query_fields = schema.is_a?(Hash) ? schema.dig('queryType', 'fields') : nil

        unless types.is_a?(Array) && query_fields.is_a?(Array)
          raise IntrospectionError,
                'The introspection response carries no usable schema: is GraphQL introspection ' \
                'enabled on this endpoint?'
        end

        [types, query_fields]
      end

      # The metadata is optional by design; one malformed entry must degrade to
      # the same fallback as an unreachable endpoint, not crash the boot.
      # Only shape errors degrade: anything else is a bug that must fail loudly.
      def safe_relationship_mappings(metadata)
        parse_relationship_mappings(metadata)
      rescue TypeError, NoMethodError, KeyError => e
        ForestAdminDatasourceGraphqlHasura.logger.warn(
          '[forest_admin_datasource_graphql_hasura] Hasura metadata could not be parsed ' \
          "(#{e.class}: #{e.message}); falling back to configuration and naming conventions."
        )
        @custom_root_fields = {}
        {}
      end

      def build_type_map(types)
        types.each_with_object({}) { |type, memo| memo[type['name']] = type if type['name'] }
      end

      # Keyed by GraphQL root field, which Hasura derives from the table name,
      # prefixed by the schema outside of `public` — hence the two spellings. A
      # name claimed by two schemas is dropped rather than guessed: inheriting
      # another schema's mapping would silently produce wrong foreign keys.
      def parse_relationship_mappings(metadata)
        mappings = {}
        ambiguous = Set.new

        (metadata['sources'] || []).each do |source|
          (source['tables'] || []).each do |table|
            collect_table_mappings(table, mappings, ambiguous)
          end
        end

        ambiguous.each do |key|
          table_name = key.split('.').first
          ForestAdminDatasourceGraphqlHasura.logger.warn(
            "[forest_admin_datasource_graphql_hasura] Table name '#{table_name}' is tracked in several " \
            'Postgres schemas; its relationship metadata is ambiguous and therefore ignored.'
          )
          mappings.delete(key)
        end

        mappings
      end

      def collect_table_mappings(table, mappings, ambiguous)
        table_info = table['table']
        return unless table_info.is_a?(Hash)

        exposed = exposed_root_field(table, table_info)
        custom = normalized_root_fields(table)
        @custom_root_fields[exposed] = custom if custom.any?

        relationships = (table['object_relationships'] || []).map { |rel| [rel, :object] } +
                        (table['array_relationships'] || []).map { |rel| [rel, :array] }

        relationships.each do |(rel, kind)|
          entry = relationship_mapping(rel, kind)
          next if entry.nil?

          # The graphql-default naming convention camelizes root fields,
          # relationship fields and columns, while the metadata keeps the
          # Postgres spellings; registering both makes the lookup match — and
          # carry column names in — whichever spelling introspection exposes.
          # When both spellings coincide the snake entry stands: a wrong-case
          # mapping degrades to a skipped relationship, never a wrong one.
          snake_key = "#{exposed}.#{rel["name"]}"
          camel_key = "#{exposed.camelize(:lower)}.#{rel["name"].camelize(:lower)}"
          register_mapping(mappings, ambiguous, snake_key, entry)
          register_mapping(mappings, ambiguous, camel_key, camelized_entry(entry)) unless camel_key == snake_key
        end
      end

      def register_mapping(mappings, ambiguous, key, entry)
        ambiguous << key if mappings.key?(key) && mappings[key] != entry
        mappings[key] = entry
      end

      def camelized_entry(entry)
        mapping = entry[:mapping]&.to_h { |local, remote| [local&.camelize(:lower), remote&.camelize(:lower)] }

        { mapping: mapping, manual: entry[:manual] }
      end

      # The mapping key has to be the root field the introspection query will
      # show. Hasura derives it from the table name — prefixed by the schema
      # outside of `public`, so a bare name can only be the public table —
      # unless the metadata customizes it (`custom_root_fields.select` wins
      # over `custom_name`, which replaces the derived name).
      def exposed_root_field(table, table_info)
        custom = table.dig('configuration', 'custom_root_fields', 'select')
        custom = custom['name'] if custom.is_a?(Hash)
        custom ||= table.dig('configuration', 'custom_name')
        return custom if custom.is_a?(String)

        schema_name = table_info['schema']
        table_name = table_info['name']

        schema_name.nil? || schema_name == 'public' ? table_name : "#{schema_name}_#{table_name}"
      end

      # Every custom root field, values flattened to their string form (the
      # metadata also allows { name:, comment: } objects).
      def normalized_root_fields(table)
        config = table.dig('configuration', 'custom_root_fields')
        return {} unless config.is_a?(Hash)

        flattened = config.transform_values { |value| value.is_a?(Hash) ? value['name'] : value }

        flattened.select { |_, value| value.is_a?(String) }
      end

      # A nil column stands for the primary key of that table: a foreign key
      # constraint may reference any unique column, and which one is only
      # resolvable once the tables are parsed.
      def relationship_mapping(rel, kind)
        using = rel['using']
        return nil unless using.is_a?(Hash)

        constraint = using['foreign_key_constraint_on']
        manual = using['manual_configuration']

        if constraint
          mapping = kind == :object ? { constraint => nil } : { nil => constraint['column'] }

          { mapping: mapping, manual: false }
        elsif manual
          { mapping: manual['column_mapping'], manual: true }
        end
      end

      # Keyed by the GraphQL OBJECT type the field returns, which the list root
      # field shares whatever the root fields are renamed to — deriving a table
      # name from the `_by_pk` spelling would miss a customized select field.
      def parse_primary_keys(query_fields)
        query_fields.each_with_object({}) do |field, memo|
          next unless field['name'].end_with?('_by_pk', 'ByPk')

          type_name = base_type_name(field['type'])
          pk_fields = (field['args'] || []).map { |arg| arg['name'] }
          memo[type_name] = pk_fields if pk_fields.any?
        end
      end

      def parse_tables(query_fields)
        root_names = query_fields.to_set { |query_field| query_field['name'] }

        query_fields.filter_map do |field|
          table_name = field['name']
          # Only the select root returns a list: _aggregate, _by_pk and Relay
          # _connection roots all return bare objects and are rejected here.
          next unless array_type?(field['type'])

          type = @type_map[base_type_name(field['type'])]
          next unless type && type['kind'] == 'OBJECT'
          next if skip_table?([table_name, type['name']].uniq)
          next if stream_companion?(table_name, root_names)

          table = parse_table(table_name, type)
          next table unless table.primary_key.empty?

          # Forest cannot address a record without a primary key: ids, detail view
          # and every write would fail.
          ForestAdminDatasourceGraphqlHasura.logger.warn(
            "[forest_admin_datasource_graphql_hasura] Skipping table '#{table_name}': no primary key found. " \
            'Expose one in Hasura (a tracked primary key or an `id` column) to surface it in Forest Admin.'
          )
          nil
        end
      end

      # names carries the root field and the underlying type name: an exclusion
      # (or inclusion) must hold whichever spelling the user wrote, or renaming
      # a table would silently re-expose it.
      def skip_table?(names)
        # An explicit exclusion always wins; then an explicit allow-list wins over
        # the built-in exclusions, so a legitimate table whose name starts like a
        # system one stays reachable.
        return true if names.any? { |name| @configuration.excluded_tables.include?(name) }
        return false if @configuration.included_tables && (names & @configuration.included_tables).any?

        names.any? { |name| EXCLUDED_PREFIXES.any? { |prefix| name.start_with?(prefix) } } ||
          !@configuration.table_allowed?(*names)
      end

      # `<select_root>_stream` returns the same list shape as its select root,
      # so the structural check cannot tell them apart; a genuine table named
      # `data_stream` has no `data` root field and is kept.
      def stream_companion?(name, root_names)
        base = name.sub(/(_stream|Stream)\z/, '')

        base != name && root_names.include?(base)
      end

      def parse_table(table_name, type)
        fields = (type['fields'] || []).reject { |field| companion_field?(field) }
        scalars, relations = fields.partition { |field| scalar?(base_type_name(field['type'])) }
        columns = scalars.map { |field| parse_column(field, base_type_name(field['type'])) }

        Table.new(
          name: table_name,
          type_name: type['name'],
          columns: columns,
          primary_key: resolve_primary_key(type['name'], columns),
          relationships: relations.map { |field| parse_relationship(table_name, field) },
          polymorphics: [],
          root_fields: resolve_root_fields(table_name, type['name'])
        )
      end

      # The operation roots derive from the type name unless the metadata
      # renames them — same resolution the select root already gets.
      def resolve_root_fields(table_name, type_name)
        custom = @custom_root_fields[table_name] || {}

        {
          aggregate: custom['select_aggregate'] || "#{type_name}_aggregate",
          insert: custom['insert'] || "insert_#{type_name}",
          update: custom['update'] || "update_#{type_name}",
          delete: custom['delete'] || "delete_#{type_name}"
        }
      end

      # Introspection metadata and the `<relation>_aggregate` objects Hasura adds
      # next to every array relationship. The suffix alone is not enough: a scalar
      # column may legitimately be named `total_aggregate`.
      def companion_field?(field)
        return true if field['name'].start_with?('__')

        field['name'].end_with?('_aggregate') && !scalar?(base_type_name(field['type']))
      end

      def parse_relationship(table_name, field)
        entry = @relationship_mappings["#{table_name}.#{field["name"]}"]

        Relationship.new(
          name: field['name'],
          kind: array_type?(field['type']) ? :array : :object,
          remote_table: base_type_name(field['type']),
          mapping: entry&.fetch(:mapping),
          manual: entry ? entry[:manual] : nil
        )
      end

      def parse_column(field, type_name)
        # Postgres array columns are exposed by Hasura as custom scalars named
        # after the element type (`_text`, `_int4`), not as GraphQL lists.
        is_array = array_type?(field['type']) || type_name.start_with?('_')

        Column.new(
          name: field['name'],
          type: map_column_type(type_name),
          graphql_type: type_name,
          nullable: field['type']['kind'] != 'NON_NULL',
          is_primary_key: false,
          is_array: is_array,
          is_text: TEXT_TYPES.include?(type_name)
        )
      end

      # Hasura only generates a `_by_pk` query for a tracked table that has a
      # primary key, which makes it the one trustworthy signal. Inferring a key
      # from an `id` column would address records of a view — or of a tracked
      # function — through a column that carries no uniqueness.
      def resolve_primary_key(type_name, columns)
        known = @primary_keys[type_name]

        if known
          columns.each { |column| column.is_primary_key = known.include?(column.name) }

          return known
        end

        []
      end

      def scalar?(type_name)
        return true if SCALAR_TYPES.include?(type_name)

        type = @type_map[type_name]
        type ? %w[SCALAR ENUM].include?(type['kind']) : false
      end

      def array_type?(type_ref)
        return false if type_ref.nil?
        return true if type_ref['kind'] == 'LIST'

        array_type?(type_ref['ofType'])
      end

      def base_type_name(type_ref)
        return 'Unknown' if type_ref.nil?

        type_ref['name'] || base_type_name(type_ref['ofType'])
      end

      # Hasura names a Postgres array scalar after its element type, prefixed with
      # an underscore (`_int4`), so the element type drives the mapping.
      def map_column_type(graphql_type)
        graphql_type = graphql_type.delete_prefix('_')

        {
          'Int' => 'Number', 'Float' => 'Number', 'numeric' => 'Number', 'bigint' => 'Number',
          'smallint' => 'Number', 'integer' => 'Number', 'real' => 'Number',
          'double_precision' => 'Number',
          # Text, not Number: Hasura serializes money in its Postgres text form
          # ("$1,100.00"), which no numeric aggregation can consume.
          'money' => 'String',
          # Internal Postgres names, which is how Hasura names array element types
          'int2' => 'Number', 'int4' => 'Number', 'int8' => 'Number',
          'float4' => 'Number', 'float8' => 'Number', 'bool' => 'Boolean',
          'String' => 'String', 'text' => 'String', 'varchar' => 'String', 'char' => 'String',
          'bpchar' => 'String', 'citext' => 'String', 'inet' => 'String', 'ID' => 'String',
          'Boolean' => 'Boolean',
          'uuid' => 'Uuid',
          'timestamptz' => 'Date', 'timestamp' => 'Date',
          'date' => 'Dateonly',
          'time' => 'Time', 'timetz' => 'Time',
          'jsonb' => 'Json', 'json' => 'Json',
          # Text rather than Binary: Hasura returns bytea hex-encoded, and the
          # agent's binary decorator would hand back raw bytes, which a JSON
          # mutation body cannot carry.
          'bytea' => 'String'
        }.fetch(graphql_type, 'String')
      end
    end
  end
end
