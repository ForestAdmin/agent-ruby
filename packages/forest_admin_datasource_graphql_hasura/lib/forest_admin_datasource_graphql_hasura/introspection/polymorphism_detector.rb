require 'active_support/core_ext/string/inflections'

module ForestAdminDatasourceGraphqlHasura
  module Introspection
    # Recognises Rails polymorphic belongs_to associations among introspected
    # tables, from a `<base>_type`/`<base>_id` column pair backed by one Hasura
    # relationship per target, or from the `polymorphic_relations` configuration
    # when the metadata API is unreachable.
    class PolymorphismDetector
      def initialize(configuration)
        @configuration = configuration
      end

      # Fills `polymorphics` on each table and removes the per-target object
      # relationships it absorbs.
      def detect(tables)
        # Relationships reference the GraphQL type name; the merge order makes
        # the type interpretation win when it collides with another table's
        # root field name (crossed custom_root_fields renames).
        tables_by_name = tables.to_h { |table| [table.name, table] }
                               .merge(tables.to_h { |table| [table.type_name, table] })

        tables.each do |table|
          bases_of(table).each { |base| absorb(table, base, tables_by_name) }
        end
      end

      private

      def absorb(table, base, tables_by_name)
        targets = targets_of(table, base, tables_by_name)
        return if targets.empty?

        table.polymorphics << Polymorphic.new(
          name: base,
          foreign_key: "#{base}_id",
          type_field: "#{base}_type",
          targets: targets
        )

        consumed = targets.values.filter_map { |target| target[:hasura_field] }
        table.relationships.reject! { |rel| consumed.include?(rel.name) }
      end

      def bases_of(table)
        names = table.columns.map(&:name)
        configured = configured_relations(table).keys

        detected = names.filter_map do |name|
          base = name.delete_suffix('_type')
          # A column literally named `_type` leaves an empty base, which would
          # emit an unnamed association absorbing whatever joins through `_id`.
          base if name.end_with?('_type') && !base.empty? && names.include?("#{base}_id")
        end

        (detected + configured.select { |base| discriminators?(table, names, base) }).uniq
      end

      # A configured association without its column pair would emit a relation
      # referencing columns that do not exist, breaking the collection at boot.
      def discriminators?(table, names, base)
        missing = ["#{base}_type", "#{base}_id"].reject { |column| names.include?(column) }
        return true if missing.empty?

        ForestAdminDatasourceGraphqlHasura.logger.warn(
          '[forest_admin_datasource_graphql_hasura] Ignoring the configured polymorphic relation ' \
          "'#{table.name}.#{base}': column(s) #{missing.join(", ")} not found on '#{table.name}'."
        )
        false
      end

      def targets_of(table, base, tables_by_name)
        configured_tables = configured_relations(table)[base]
        foreign_key = "#{base}_id"

        candidates = table.relationships.select do |rel|
          branch?(rel, foreign_key, configured_tables, tables_by_name)
        end

        candidates.group_by(&:remote_table).each_with_object({}) do |(remote_table, relationships), memo|
          target_table = tables_by_name[remote_table]
          next unless target_table
          next if ambiguous_branch?(table, base, target_table.name, relationships)

          relationship = relationships.first
          memo[class_name_of(target_table)] = {
            table: target_table.name,
            hasura_field: relationship.name,
            primary_key: relationship.mapping&.values&.first || target_table.primary_key.first || 'id'
          }
        end
      end

      # Without the Hasura metadata every mapping is unknown, so two object
      # relationships towards the same configured target are indistinguishable:
      # one may be a plain belongs_to, and absorbing it would silently delete a
      # legitimate relation. Refuse to guess.
      def ambiguous_branch?(table, base, remote_table, relationships)
        return false if relationships.size == 1

        ForestAdminDatasourceGraphqlHasura.logger.warn(
          "[forest_admin_datasource_graphql_hasura] '#{table.name}.#{base}' cannot absorb a branch " \
          "towards '#{remote_table}': the relationships #{relationships.map(&:name).join(", ")} are " \
          'equally plausible and one may be a plain belongs_to. That target is skipped.'
        )
        true
      end

      def branch?(relationship, foreign_key, configured_tables, tables_by_name)
        return false unless relationship.kind == :object
        # A known mapping is checked even when the target is configured: a table
        # may hold both an ordinary relationship and a polymorphic branch towards
        # the same target, and they must not be mistaken for one another.
        return false unless relationship.mapping.nil? || relationship.mapping.keys == [foreign_key]

        if configured_tables
          # The configuration names tables; the relationship carries the GraphQL
          # type name, which custom_root_fields can decouple from the root field.
          target = tables_by_name[relationship.remote_table]

          # & rather than intersect?, which needs Ruby >= 3.1.
          return (configured_tables & [target&.name, target&.type_name].compact).any?
        end

        # A relationship backed by a real foreign key constraint is monomorphic by
        # definition: accepting one here would absorb a legitimate belongs_to
        # whenever an unrelated `<base>_type` enum sits next to `<base>_id`.
        relationship.manual
      end

      # Like type_values, the configuration accepts the root field name or the
      # underlying type name.
      def configured_relations(table)
        @configuration.polymorphic_relations[table.name] ||
          @configuration.polymorphic_relations[table.type_name] ||
          {}
      end

      def class_name_of(table)
        @configuration.type_values[table.name] ||
          @configuration.type_values[table.type_name] ||
          table.type_name.classify
      end
    end
  end
end
