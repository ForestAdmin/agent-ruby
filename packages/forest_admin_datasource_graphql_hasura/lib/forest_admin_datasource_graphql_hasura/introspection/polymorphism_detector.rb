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
        tables_by_name = tables.to_h { |table| [table.name, table] }

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
        configured = @configuration.polymorphic_relations[table.name]&.keys || []

        detected = names.filter_map do |name|
          base = name.delete_suffix('_type')
          base if name.end_with?('_type') && names.include?("#{base}_id")
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
        configured_tables = @configuration.polymorphic_relations.dig(table.name, base)
        foreign_key = "#{base}_id"

        candidates = table.relationships.select { |rel| branch?(rel, foreign_key, configured_tables) }

        candidates.each_with_object({}) do |rel, memo|
          target_table = tables_by_name[rel.remote_table]
          next unless target_table

          memo[class_name_of(rel.remote_table)] = {
            table: rel.remote_table,
            hasura_field: rel.name,
            primary_key: rel.mapping&.values&.first || target_table.primary_key.first || 'id'
          }
        end
      end

      def branch?(relationship, foreign_key, configured_tables)
        return false unless relationship.kind == :object
        # A known mapping is checked even when the target is configured: a table
        # may hold both an ordinary relationship and a polymorphic branch towards
        # the same target, and they must not be mistaken for one another.
        return false unless relationship.mapping.nil? || relationship.mapping.keys == [foreign_key]
        return configured_tables.include?(relationship.remote_table) if configured_tables

        # A relationship backed by a real foreign key constraint is monomorphic by
        # definition: accepting one here would absorb a legitimate belongs_to
        # whenever an unrelated `<base>_type` enum sits next to `<base>_id`.
        relationship.manual
      end

      def class_name_of(table_name)
        @configuration.type_values[table_name] || table_name.classify
      end
    end
  end
end
