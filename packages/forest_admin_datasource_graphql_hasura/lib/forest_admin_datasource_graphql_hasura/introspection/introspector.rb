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
      EXCLUDED_SUFFIXES = %w[_aggregate _by_pk _stream _connection].freeze

      def initialize(client, configuration)
        @client = client
        @configuration = configuration
      end

      # @return [Array<Table>]
      def introspect
        schema = @client.execute(INTROSPECTION_QUERY)
        raise IntrospectionError, 'Introspection query returned no schema' unless schema&.key?('__schema')

        metadata = @client.fetch_metadata

        @type_map = build_type_map(schema['__schema']['types'])
        @relationship_mappings = metadata ? parse_relationship_mappings(metadata) : {}
        @primary_keys = parse_primary_keys(schema['__schema']['queryType']['fields'])

        tables = parse_tables(schema['__schema']['queryType']['fields'])
        PolymorphismDetector.new(@configuration).detect(tables)

        tables
      end

      private

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

        metadata['sources'].each do |source|
          source['tables'].each do |table|
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
        schema_name = table.dig('table', 'schema')
        table_name = table.dig('table', 'name')
        prefixed = schema_name.nil? || schema_name == 'public' ? nil : "#{schema_name}_#{table_name}"

        relationships = (table['object_relationships'] || []).map { |rel| [rel, :object] } +
                        (table['array_relationships'] || []).map { |rel| [rel, :array] }

        relationships.each do |(rel, kind)|
          entry = relationship_mapping(rel, kind)
          next if entry.nil?

          [table_name, prefixed].compact.each do |name|
            key = "#{name}.#{rel["name"]}"
            ambiguous << key if mappings.key?(key) && mappings[key] != entry
            mappings[key] = entry
          end
        end
      end

      # A nil column stands for the primary key of that table: a foreign key
      # constraint may reference any unique column, and which one is only
      # resolvable once the tables are parsed.
      def relationship_mapping(rel, kind)
        using = rel['using']
        constraint = using['foreign_key_constraint_on']
        manual = using['manual_configuration']

        if constraint
          mapping = kind == :object ? { constraint => nil } : { nil => constraint['column'] }

          { mapping: mapping, manual: false }
        elsif manual
          { mapping: manual['column_mapping'], manual: true }
        end
      end

      def parse_primary_keys(query_fields)
        query_fields.each_with_object({}) do |field, memo|
          next unless field['name'].end_with?('_by_pk')

          table_name = field['name'].delete_suffix('_by_pk')
          pk_fields = (field['args'] || []).map { |arg| arg['name'] }
          memo[table_name] = pk_fields if pk_fields.any?
        end
      end

      def parse_tables(query_fields)
        query_fields.filter_map do |field|
          table_name = field['name']
          next if skip_table?(table_name)

          type = @type_map[base_type_name(field['type'])]
          next unless type && type['kind'] == 'OBJECT'

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

      def skip_table?(name)
        EXCLUDED_PREFIXES.any? { |prefix| name.start_with?(prefix) } ||
          EXCLUDED_SUFFIXES.any? { |suffix| name.end_with?(suffix) } ||
          !@configuration.table_allowed?(name)
      end

      def parse_table(table_name, type)
        fields = (type['fields'] || []).reject { |field| companion_field?(field['name']) }
        scalars, relations = fields.partition { |field| scalar?(base_type_name(field['type'])) }
        columns = scalars.map { |field| parse_column(field, base_type_name(field['type'])) }

        Table.new(
          name: table_name,
          columns: columns,
          primary_key: resolve_primary_key(table_name, columns),
          relationships: relations.map { |field| parse_relationship(table_name, field) },
          polymorphics: []
        )
      end

      # Introspection metadata and the `<relation>_aggregate` fields Hasura adds
      # next to every array relationship — neither are columns or relations.
      def companion_field?(name)
        name.start_with?('__') || name.end_with?('_aggregate')
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

      # Hasura only generates a `_by_pk` query for tables that have a primary
      # key. Anything else is left without one: guessing a composite key out of
      # the `*_id` columns produced wrong record ids.
      def resolve_primary_key(table_name, columns)
        known = @primary_keys[table_name]

        if known
          columns.each { |column| column.is_primary_key = known.include?(column.name) }

          return known
        end

        id_column = columns.find { |column| column.name == 'id' }

        if id_column
          id_column.is_primary_key = true

          return ['id']
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

      def map_column_type(graphql_type)
        {
          'Int' => 'Number', 'Float' => 'Number', 'numeric' => 'Number', 'bigint' => 'Number',
          'smallint' => 'Number', 'integer' => 'Number', 'real' => 'Number',
          'double_precision' => 'Number', 'money' => 'Number',
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
