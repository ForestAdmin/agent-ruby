module ForestAdminAgent
  module Utils
    # The scope of a collection reached through a to-one relation empties the related record rather
    # than filtering the root rows: a scope on `accounts` restricts which accounts are seen, never
    # which `cards` exist.
    class RelationScopes
      RelationScope = Struct.new(:path, :collection, :scope)

      def initialize(scopes = [])
        @scopes = scopes
      end

      def with_scope_fields(projection)
        scope_fields = @scopes.map { |relation| relation.scope.projection.nest(prefix: relation.path) }

        projection.union(*scope_fields)
      end

      def redact(records, projection, timezone)
        return records if @scopes.empty?

        out_of_scope_paths = records.map { |record| out_of_scope_paths(record, timezone) }

        projection.apply(records).each_with_index do |record, index|
          out_of_scope_paths[index].each { |path| self.class.clear(record, path) }
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

      def out_of_scope_paths(record, timezone)
        stringified = ForestAdminDatasourceToolkit::Utils::HashHelper.convert_keys(record, :to_s)

        @scopes.filter_map do |relation_scope|
          related = ForestAdminDatasourceToolkit::Utils::Record.field_value(stringified, relation_scope.path)

          relation_scope.path if related && !relation_scope.scope.match(related, relation_scope.collection, timezone)
        end
      end
    end
  end
end
