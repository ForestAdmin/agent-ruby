module ForestAdminAgent
  module Utils
    # The scope of a collection reached through a to-one relation empties the related record rather
    # than filtering the root rows: a scope on `accounts` restricts which accounts are seen, never
    # which `cards` exist.
    #
    # Each related collection is checked with one query under its own scope, so the datasource
    # compares values exactly as it does when listing that collection.
    class RelationScopes
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

      RelationScope = Struct.new(:path, :collection, :scope)

      def initialize(scopes = [], caller = nil)
        @scopes = scopes
        @caller = caller
      end

      def with_scope_fields(projection)
        key_fields = @scopes.map do |relation|
          Projection.new(ForestAdminDatasourceToolkit::Utils::Schema.primary_keys(relation.collection))
                    .nest(prefix: relation.path)
        end

        projection.union(*key_fields)
      end

      def redact(records, projection)
        return records if @scopes.empty?

        stringified = records.map { |record| ForestAdminDatasourceToolkit::Utils::HashHelper.convert_keys(record, :to_s) }
        out_of_scope = @scopes.map do |relation_scope|
          [relation_scope.path, out_of_scope_rows(stringified, relation_scope)]
        end

        # Only the keys added for the check are removed: the datasource may return others the
        # serializer needs, such as the foreign key of a polymorphic relation.
        added_fields = with_scope_fields(projection) - projection
        stringified.each_with_index do |record, index|
          added_fields.each { |path| self.class.remove(record, path) }
          out_of_scope.each { |path, rows| self.class.clear(record, path) if rows.include?(index) }
        end
      end

      def self.remove(record, path)
        relation, rest = path.split(':', 2)

        if rest.nil?
          record.delete(relation)
        elsif record[relation].is_a?(Hash)
          remove(record[relation], rest)
        end
      end

      def self.clear(record, path)
        relation, rest = path.split(':', 2)

        if rest.nil?
          record[relation] = nil
        elsif record[relation]
          clear(record[relation], rest)
        end
      end

      private

      # The indexes of the rows whose related record at this path the scope hides.
      def out_of_scope_rows(records, relation_scope)
        collection = relation_scope.collection
        related = records.map { |record| ForestAdminDatasourceToolkit::Utils::Record.field_value(record, relation_scope.path) }
        present = related.compact
        return [] if present.empty?

        visible = keys_in_scope(collection, relation_scope.scope, present)

        related.each_index.select do |index|
          related[index] && !visible.include?(ForestAdminDatasourceToolkit::Utils::Record.primary_keys(collection,
                                                                                                       related[index]))
        end
      end

      def keys_in_scope(collection, scope, related)
        primary_keys = ForestAdminDatasourceToolkit::Utils::Schema.primary_keys(collection)
        filter = Filter.new(
          condition_tree: ConditionTreeFactory.intersect([scope,
                                                          ConditionTreeFactory.match_records(collection, related)])
        )

        collection.list(@caller, filter, Projection.new(primary_keys)).map do |record|
          ForestAdminDatasourceToolkit::Utils::Record.primary_keys(
            collection, ForestAdminDatasourceToolkit::Utils::HashHelper.convert_keys(record, :to_s)
          )
        end
      end
    end
  end
end
