module ForestAdminDatasourceToolkit
  module Utils
    class FieldPath
      POLYMORPHIC_MANY_TO_ONE = 'PolymorphicManyToOne'.freeze

      # The collections whose column a path ends on — the ones a read permission applies to.
      # Collections crossed on the way are joins, not read targets, so they are not returned.
      #
      # Several names come back for a path ending on a polymorphic relation: it carries no
      # discriminant, so any record may resolve to any of its targets and none can be ruled out. The
      # list is empty for a polymorphic relation declaring no target at all, which the caller counts
      # as denied — an empty list is a path that resolves to nothing, not a path that needs nothing.
      #
      # A prefix naming no relation raises rather than falling back to +collection+. The caller pins
      # the collection it asked about to readable, so falling back would turn "this path does not
      # resolve" into "this path is allowed".
      #
      # A path with no prefix at all is a column of +collection+ itself, and so is allowed. Two
      # customisations reach a related collection through one deliberately: +import_field+, and an
      # +add_field+ whose dependencies cross a relation, both register a root-level column that the
      # operator and sorting layers rewrite into a relation path below this guard. Like a scope or a
      # +replace_search+, they are the customer's own choice of what a role reaches through a column
      # it can read.
      def self.leaf_collection_names(collection, path)
        index = path.index(':')

        return [collection.name] if index.nil?

        relation = relation_at(collection, path[0...index])

        return relation.foreign_collections if relation.type == POLYMORPHIC_MANY_TO_ONE

        leaf_collection_names(
          collection.datasource.get_collection(relation.foreign_collection),
          path[(index + 1)..]
        )
      end

      def self.relation_at(collection, name)
        field = collection.schema[:fields][name]

        if field.nil? || field.type == 'Column'
          raise Exceptions::ForestException, "Relation not found: '#{collection.name}.#{name}'"
        end

        field
      end

      private_class_method :relation_at
    end
  end
end
