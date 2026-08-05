require 'active_support/core_ext/string/inflections'

module ForestAdminDatasourceGraphqlHasura
  module Introspection
    # Converts introspected tables into Forest Admin field schemas.
    #
    # Collections are named after the Rails class name, because the Forest
    # serializer resolves the target of a PolymorphicManyToOne from the raw value
    # of the type column — both namings have to match.
    class SchemaConverter
      ColumnSchema = ForestAdminDatasourceToolkit::Schema::ColumnSchema
      Relations = ForestAdminDatasourceToolkit::Schema::Relations
      Operators = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators

      BASE_OPERATORS = [
        Operators::EQUAL, Operators::NOT_EQUAL, Operators::PRESENT, Operators::MISSING,
        Operators::IN, Operators::NOT_IN
      ].freeze

      # PRESENT is deliberately absent: on a text column an empty string is not
      # "present", so the toolkit derives it from NOT_IN as `NotIn [nil, '']`.
      STRING_OPERATORS = [
        Operators::EQUAL, Operators::NOT_EQUAL, Operators::MISSING, Operators::IN, Operators::NOT_IN,
        Operators::CONTAINS, Operators::NOT_CONTAINS, Operators::I_CONTAINS, Operators::NOT_I_CONTAINS,
        Operators::STARTS_WITH, Operators::I_STARTS_WITH, Operators::ENDS_WITH, Operators::I_ENDS_WITH,
        Operators::LIKE, Operators::I_LIKE
      ].freeze

      COMPARABLE_OPERATORS = (BASE_OPERATORS + [Operators::GREATER_THAN, Operators::LESS_THAN,
                                                Operators::GREATER_THAN_OR_EQUAL,
                                                Operators::LESS_THAN_OR_EQUAL]).freeze

      DATE_OPERATORS = (COMPARABLE_OPERATORS + [Operators::BEFORE, Operators::AFTER]).freeze

      # Hasura's array comparison expressions have no pattern matching, and
      # `IncludesAll` has no equivalent the filter converter can emit.
      ARRAY_OPERATORS = [Operators::EQUAL, Operators::NOT_EQUAL, Operators::PRESENT,
                         Operators::MISSING].freeze

      def initialize(tables, configuration)
        @tables = tables
        # Two indexes rather than one merged map: a table's type_name may equal
        # another table's root field name (crossed custom_root_fields renames),
        # and each lookup knows which spelling it holds.
        @tables_by_root = tables.to_h { |table| [table.name, table] }
        @tables_by_type = tables.to_h { |table| [table.type_name, table] }
        @configuration = configuration
      end

      # Rails stores the class name derived from the Postgres table, which the
      # GraphQL type name follows — not the root field, which custom_root_fields
      # can rename freely. Callers pass root field names, so only the root index
      # is consulted; type_values accepts either name.
      def rails_class_name_of(table_name)
        table = @tables_by_root[table_name]

        @configuration.type_values[table_name] ||
          (table && @configuration.type_values[table.type_name]) ||
          (table&.type_name || table_name).classify
      end

      # 'Banking::Account' -> 'Banking__Account'
      def collection_name_of(table_name)
        rails_class_name_of(table_name).gsub('::', '__')
      end

      def build_fields(table)
        fields = {}
        composite_key = table.primary_key.size > 1

        table.columns.each do |column|
          fields[column.name] = convert_column(column, composite_key: composite_key)
        end

        add_polymorphics(table, fields)
        add_relationships(table, fields)
        add_reverse_polymorphics(table, fields)

        fields
      end

      private

      # A relationship references the GraphQL type; the root-field spelling is
      # accepted as a fallback, and on a collision the type interpretation wins.
      def resolve_table(reference)
        @tables_by_type[reference] || @tables_by_root[reference]
      end

      # A single-column key is database-generated in the schemas Hasura fronts
      # (serial, uuid default), and the writes persist explicit nils — which
      # would override that default — so it stays read-only. A composite key is
      # application-assigned (a join table has no default to fall back on):
      # keeping it read-only would make the table impossible to create through.
      def convert_column(column, composite_key:)
        read_only = column.is_primary_key && !composite_key

        ColumnSchema.new(
          column_type: column.is_array ? [column.type] : column.type,
          filter_operators: operators_for(column),
          is_primary_key: column.is_primary_key,
          is_read_only: read_only,
          is_sortable: !column.is_array,
          # The capabilities route publishes this flag, so anything but the
          # foreign keys of mark_groupable_foreign_keys would have the UI offer a
          # group-by that grouped_aggregate then rejects.
          is_groupable: false,
          default_value: nil,
          validation: column.nullable || read_only ? [] : [{ operator: Operators::PRESENT }]
        )
      end

      def add_polymorphics(table, fields)
        table.polymorphics.each do |polymorphic|
          # A physical column of that name wins: replacing it would drop it from
          # the schema, leaving it neither readable nor writable.
          if fields.key?(polymorphic.name)
            ForestAdminDatasourceGraphqlHasura.logger.warn(
              "[forest_admin_datasource_graphql_hasura] '#{table.name}' has a column named " \
              "'#{polymorphic.name}', so its polymorphic association is not exposed. Rename either the " \
              'column or the association to surface both.'
            )
            next
          end

          fields[polymorphic.name] = convert_polymorphic(polymorphic)
          lock_discriminators(table, polymorphic, fields)
        end
      end

      # The widget drives the discriminator columns, so they are read-only and
      # cannot carry a Present validation the user could never satisfy. The
      # exception is a discriminator belonging to a composite primary key (a
      # Rails taggings table): locking it would make the row impossible to
      # create, which the composite-key carve-out of convert_column exists to
      # prevent.
      def lock_discriminators(table, polymorphic, fields)
        composite = table.primary_key.size > 1

        [polymorphic.foreign_key, polymorphic.type_field].each do |column|
          field = fields[column]
          next if field.nil?
          next if composite && table.primary_key.include?(column)

          field.is_read_only = true
          field.validation = []
        end
      end

      def convert_polymorphic(polymorphic)
        Relations::PolymorphicManyToOneSchema.new(
          foreign_key: polymorphic.foreign_key,
          foreign_key_type_field: polymorphic.type_field,
          foreign_collections: polymorphic.targets.keys.map { |type_value| type_value.gsub('::', '__') },
          foreign_key_targets: polymorphic.targets.to_h do |type_value, target|
            [type_value.gsub('::', '__'), target[:primary_key]]
          end
        )
      end

      def add_relationships(table, fields)
        table.relationships.each do |relationship|
          name, schema = convert_relationship(table, relationship)
          next if schema.nil?

          if fields.key?(name)
            ForestAdminDatasourceGraphqlHasura.logger.warn(
              "[forest_admin_datasource_graphql_hasura] Relationship '#{name}' on '#{table.name}' " \
              'shares its name with another field, which wins; rename one of them to surface both.'
            )
            next
          end

          fields[name] = schema
        end
      end

      def convert_relationship(table, relationship)
        if relationship.kind == :object
          convert_object_relationship(table, relationship)
        else
          convert_array_relationship(table, relationship)
        end
      end

      def convert_object_relationship(table, relationship)
        remote = resolve_table(relationship.remote_table)

        # A relation towards a table the datasource does not expose (excluded, or
        # dropped for want of a primary key) breaks schema generation at boot.
        unless remote
          skip_relationship(table, relationship, "target table '#{relationship.remote_table}' is not exposed")

          return [relationship.name, nil]
        end

        return [relationship.name, nil] unless single_column_mapping?(table, relationship)

        foreign_key = relationship.mapping&.keys&.first || "#{relationship.name}_id"

        unless table.columns.any? { |column| column.name == foreign_key }
          skip_relationship(table, relationship, "foreign key '#{foreign_key}' does not exist")

          return [relationship.name, nil]
        end

        [relationship.name, Relations::ManyToOneSchema.new(
          foreign_collection: collection_name_of(remote.name),
          foreign_key: foreign_key,
          foreign_key_target: relationship.mapping&.values&.first || primary_key_of(remote)
        )]
      end

      def convert_array_relationship(table, relationship)
        remote = resolve_table(relationship.remote_table)
        return [relationship.name, nil] unless remote
        return [relationship.name, nil] if covered_by_reverse_polymorphic?(table, relationship, remote)
        return [relationship.name, nil] unless single_column_mapping?(table, relationship)

        # The conventional foreign key follows the underlying table (type_name),
        # not a root field custom_root_fields may have renamed.
        origin_key = relationship.mapping&.values&.first || "#{table.type_name.singularize}_id"

        unless remote.columns.any? { |column| column.name == origin_key }
          skip_relationship(table, relationship, "origin key '#{origin_key}' does not exist on " \
                                                 "'#{relationship.remote_table}'")

          return [relationship.name, nil]
        end

        [relationship.name, Relations::OneToManySchema.new(
          foreign_collection: collection_name_of(remote.name),
          origin_key: origin_key,
          origin_key_target: relationship.mapping&.keys&.first || primary_key_of(table)
        )]
      end

      # Requires a known column mapping: without the Hasura metadata, a
      # same-named array relationship may well be a regular has_many, and
      # replacing it would silently list the wrong records.
      def covered_by_reverse_polymorphic?(table, relationship, remote)
        return false if relationship.mapping.nil?

        remote.polymorphics.any? { |polymorphic| reverse_of?(relationship, table, polymorphic) }
      end

      # Both ends have to line up: an array relationship joining the polymorphic
      # foreign key to another local column (`{ 'external_id' => 'commentable_id' }`)
      # is a different relationship, and the PolymorphicOneToMany that would
      # replace it queries by the primary key instead.
      def reverse_of?(relationship, table, polymorphic)
        this_class_name = rails_class_name_of(table.name)
        target = polymorphic.targets[this_class_name]
        return false if target.nil?
        return false unless relationship.mapping&.values&.first == polymorphic.foreign_key

        local_key = relationship.mapping.keys.first

        local_key.nil? || local_key == target[:primary_key]
      end

      def single_column_mapping?(table, relationship)
        return true if relationship.mapping.nil? || relationship.mapping.size <= 1

        skip_relationship(table, relationship,
                          'its Hasura column mapping spans several columns, which Forest Admin ' \
                          'relations cannot express')
        false
      end

      # One PolymorphicOneToMany per polymorphic belongs_to targeting this table,
      # named after the matching Hasura array relationship when there is one.
      def add_reverse_polymorphics(table, fields)
        this_class_name = rails_class_name_of(table.name)

        @tables.each do |child|
          child.polymorphics.each do |polymorphic|
            next unless polymorphic.targets.key?(this_class_name)

            name = reverse_polymorphic_name(table, child, polymorphic, fields)
            next unless name

            fields[name] = Relations::PolymorphicOneToManySchema.new(
              foreign_collection: collection_name_of(child.name),
              origin_key: polymorphic.foreign_key,
              origin_key_target: polymorphic.targets[this_class_name][:primary_key],
              origin_type_field: polymorphic.type_field,
              origin_type_value: this_class_name
            )
          end
        end
      end

      def reverse_polymorphic_name(table, child, polymorphic, fields)
        array_relationship = table.relationships.find do |rel|
          rel.kind == :array && resolve_table(rel.remote_table) == child && reverse_of?(rel, table, polymorphic)
        end

        candidates = [array_relationship&.name, child.name, "#{child.name}_#{polymorphic.name}"].compact.uniq
        name = candidates.find { |candidate| !fields.key?(candidate) }

        unless name
          ForestAdminDatasourceGraphqlHasura.logger.warn(
            '[forest_admin_datasource_graphql_hasura] Cannot expose the reverse of ' \
            "'#{child.name}.#{polymorphic.name}' on '#{table.name}': the names #{candidates.join(", ")} " \
            'are already taken. Rename the conflicting field or declare a Hasura array relationship.'
          )
        end

        name
      end

      def primary_key_of(table)
        table.primary_key.first || 'id'
      end

      def operators_for(column)
        return ARRAY_OPERATORS if column.is_array

        case column.type
        when 'String' then column.is_text ? STRING_OPERATORS : BASE_OPERATORS
        when 'Number' then COMPARABLE_OPERATORS
        when 'Date', 'Dateonly', 'Time' then DATE_OPERATORS
        else BASE_OPERATORS
        end
      end

      def skip_relationship(table, relationship, reason)
        ForestAdminDatasourceGraphqlHasura.logger.warn(
          "[forest_admin_datasource_graphql_hasura] Skipping relationship '#{relationship.name}' " \
          "on '#{table.name}': #{reason}. Declare it in the Hasura metadata or through the " \
          "'polymorphic_relations' option."
        )
      end
    end
  end
end
