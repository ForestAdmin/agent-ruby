module ForestAdminDatasourceIntercom
  module Collections
    # Intercom joins nothing, so relation filters must be answered here: the agent publishes a
    # many-to-one filterable as soon as any target column is. A null foreign key matches no
    # relation filter, negated ones included, like a join.
    module Relations # rubocop:disable Metrics/ModuleLength
      ManyToOneSchema = ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema
      ManyToManySchema = ForestAdminDatasourceToolkit::Schema::Relations::ManyToManySchema
      OneToManySchema = ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema
      Filter = ForestAdminDatasourceToolkit::Components::Query::Filter
      Projection = ForestAdminDatasourceToolkit::Components::Query::Projection
      Operators = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators
      Branch = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeBranch
      Leaf = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf

      # What a relation condition comes to when the target matched no record: no
      # row can satisfy it. It is a value rather than an empty condition because
      # the two tiers spell "match nothing" differently -- in memory an `in []`
      # says it, while Intercom's search DSL has no way to.
      NOTHING = :matches_nothing

      # The group a relation condition expands into, told apart from a group the
      # operator wrote. Two things hang on the difference: this one may be
      # inlined into a parent aggregating the same way -- the level it adds is
      # one nobody budgeted for -- and a tier refusing it can name the relation
      # rather than a shape the operator never wrote.
      class RelationBranch < Branch
        attr_reader :relation_field

        def initialize(aggregator, conditions, relation_field)
          @relation_field = relation_field
          super(aggregator, conditions)
        end
      end

      protected

      # Every relation of this package points at a collection keyed by `id` and
      # is read-only: nothing in this lot writes, and an editable relation would
      # offer an association the collection cannot perform.
      #
      # Published unfilterable where the endpoint filters nothing on the key, so
      # the interface does not offer the traversal `check_relation_filterable!`
      # would refuse.
      def add_many_to_one(name, foreign_collection:, foreign_key:)
        add_field(name, ManyToOneSchema.new(foreign_collection: foreign_collection,
                                            foreign_key: foreign_key,
                                            foreign_key_target: 'id',
                                            is_read_only: true,
                                            is_filterable: relation_key_filterable?(foreign_key)))
      end

      # Served by the agent as `origin_key equals <id>` on the target, which must answer it.
      def add_one_to_many(name, foreign_collection:, origin_key:)
        add_field(name, OneToManySchema.new(foreign_collection: foreign_collection,
                                            origin_key: origin_key,
                                            origin_key_target: 'id',
                                            is_read_only: true))
      end

      def add_many_to_many(name, foreign_collection:, through_collection:, origin_key:, foreign_key:)
        add_field(name, ManyToManySchema.new(foreign_collection: foreign_collection,
                                             through_collection: through_collection,
                                             origin_key: origin_key, origin_key_target: 'id',
                                             foreign_key: foreign_key, foreign_key_target: 'id',
                                             is_read_only: true))
      end

      # `records` are the unprojected rows, where the foreign keys live. One read per target
      # collection per page, shared by every relation pointing at it.
      def embed_relations(caller, records, rows, projection)
        asked = many_to_one_asked(projection)
        return if asked.empty?

        indexed = indexed_targets(caller, records, asked)

        asked.each do |name, relation, wanted|
          rows_of_target = indexed[relation.foreign_collection]

          # Nil rather than absent when an id names no record: a teammate who
          # left the workspace reads as no teammate, not as a broken row. Sliced
          # back to what this relation asked for, the read having been widened to
          # the union of what every relation on that collection did.
          records.each_with_index do |record, index|
            target_row = rows_of_target[record[relation.foreign_key]]
            rows[index][name] = target_row&.slice(*wanted)
          end
        end
      end

      # Trades each `relation:field` leaf for a condition on the foreign key, built by the block
      # from the ids the target matched.
      def rewrite_relation_conditions(caller, node, &builder)
        case node
        when Branch then rewrite_branch(caller, node, &builder)
        when Leaf then relation_leaf?(node) ? rewrite_relation_leaf(caller, node, &builder) : node
        else node
        end
      end

      private

      def relation_leaf?(node)
        node.is_a?(Leaf) && node.field.to_s.include?(':')
      end

      def relations_asked(projection)
        Projection.new(Array(projection).map(&:to_s)).relations
      end

      # The many-to-one relations the projection named, each with the columns it
      # asked of its target. The target's own key travels with them whether or
      # not it was asked for: it is what the rows are indexed by here, and what
      # makes the nested row a link rather than a label in the interface.
      def many_to_one_asked(projection)
        relations_asked(projection).filter_map do |relation_name, sub_projection|
          relation = fields[relation_name]
          next unless relation.is_a?(ManyToOneSchema)

          columns = Array(sub_projection).map(&:to_s)
          refuse_two_hop_projection!(relation_name, relation, columns)

          [relation_name, relation, columns.union([relation.foreign_key_target])]
        end
      end

      # `admin_assignee:teams:name` is a projection Forest's own parser builds
      # and this cannot answer: it nests one target row under the relation name,
      # not a tree of them, so the second hop would be dropped by the target's
      # projection and the column would come back missing from a row that looks
      # complete. Refused by name, like the filter that reaches that deep --
      # `refuse_two_hops!` is its counterpart.
      def refuse_two_hop_projection!(relation_name, relation, columns)
        deep = columns.select { |column| column.include?(':') }
        return if deep.empty?

        raise UnsupportedOperatorError,
              "#{name} cannot read #{deep.map { |column| "#{relation_name}:#{column}".inspect }.join(", ")}: it " \
              'reaches through two relations, and this datasource resolves one. Read the column from a record ' \
              "page of #{relation.foreign_collection}, one hop away."
      end

      def indexed_targets(caller, records, asked)
        asked.group_by { |_, relation, _| relation.foreign_collection }
             .transform_values { |group| target_rows(caller, records, group) }
      end

      # Past what the target resolves at all, refused: a partly resolved page would show nil where
      # a record exists.
      def target_rows(caller, records, group)
        relation = group.first[1]
        ids = group.flat_map { |_, rel, _| records.filter_map { |record| record[rel.foreign_key] } }.uniq
        return {} if ids.empty?

        collection = foreign_collection(relation)
        refuse_relation_fan_out!(group, collection, ids.size) if beyond_reach?(collection, ids.size)

        target = relation.foreign_key_target
        wanted = Projection.new(group.flat_map { |_, _, columns| columns }.uniq)

        read_targets(caller, collection, target, ids, wanted).to_h { |row| [row[target], row] }
      end

      def beyond_reach?(collection, count)
        limit = collection.max_resolvable_ids

        !limit.nil? && count > limit
      end

      def read_targets(caller, collection, target, ids, wanted)
        chunk = collection.ids_per_read
        slices = chunk ? ids.each_slice(chunk).to_a : [ids]

        slices.flat_map do |slice|
          collection.list(caller, Filter.new(condition_tree: Leaf.new(target, Operators::IN, slice)), wanted)
        end
      end

      # Names the relations rather than the key they resolve to: what the
      # operator can act on is the column they put in the view or the export,
      # and how many rows they asked for at once.
      def refuse_relation_fan_out!(group, collection, count)
        asked = group.map { |relation_name, _, _| relation_name }.join(', ')

        raise UnsupportedOperatorError,
              "#{name} cannot resolve #{asked} over this read: it names #{count} distinct #{collection.name} " \
              'records and Intercom has no bulk read for that collection, so this resolves at most ' \
              "#{collection.max_resolvable_ids} of them per read -- one request each. Read fewer rows at a time, " \
              'or leave the relation out of the projection: a relation resolved for part of a page would show no ' \
              'record where one exists.'
      end

      def rewrite_branch(caller, branch, &builder)
        rewritten = Array(branch.conditions).map { |node| rewrite_relation_conditions(caller, node, &builder) }

        if branch.aggregator.to_s.casecmp('or').zero?
          kept = rewritten.reject { |node| node == NOTHING }
          kept.empty? ? NOTHING : Branch.new(branch.aggregator, absorb_groups(branch.aggregator, kept))
        elsif rewritten.include?(NOTHING)
          NOTHING
        else
          Branch.new(branch.aggregator, absorb_groups(branch.aggregator, rewritten))
        end
      end

      # `or(x, or(a, b))` becomes `or(x, a, b)`, saving the nesting level a relation expansion
      # adds. Only relation groups are inlined, never groups the operator wrote.
      def absorb_groups(aggregator, nodes)
        absorbed = nodes.flat_map do |node|
          inlinable_group?(node, aggregator) ? Array(node.conditions) : [node]
        end

        absorb_relation_group?(absorbed.size) ? absorbed : nodes
      end

      def inlinable_group?(node, aggregator)
        node.is_a?(RelationBranch) && node.aggregator.to_s.casecmp(aggregator.to_s).zero?
      end

      # Hook for a tier that bounds how many conditions a group may hold: past
      # that, the nested form is the one that fits, and the level it costs is
      # spent rather than the width.
      def absorb_relation_group?(_size) = true

      def rewrite_relation_leaf(caller, leaf)
        name, path = leaf.field.to_s.split(':', 2)
        relation = fields[name]
        refuse_unknown_relation!(leaf, name) unless relation.is_a?(ManyToOneSchema)
        refuse_two_hops!(leaf) if path.include?(':')

        check_relation_filterable!(leaf, relation)

        ids = matching_ids(caller, relation, Leaf.new(path, leaf.operator, leaf.value))
        return NOTHING if ids.empty?

        yield(relation.foreign_key, ids, leaf)
      end

      # Hooks for a tier that cannot filter on every foreign key it declares a
      # relation on. Answered before the target is read: a refusal that spends a
      # request first costs exactly what it refuses to do.
      def relation_key_filterable?(_key) = true

      def check_relation_filterable!(_leaf, _relation); end

      # Which records of the target the condition names, asked of the target
      # itself: it owns what its columns can be filtered with, and it answers
      # over every record Intercom holds rather than over a page of them.
      def matching_ids(caller, relation, leaf)
        target = relation.foreign_key_target
        filter = Filter.new(condition_tree: leaf, page: match_page)

        foreign_collection(relation)
          .list(caller, filter, Projection.new([target]))
          .filter_map { |row| row[target] }
          .uniq
      end

      # How much of the target a relation condition may read; unbounded for in-memory targets.
      def match_page = nil

      # The target as the datasource holds it, undecorated -- so a permission
      # scope or a segment defined on the target does not narrow what a relation
      # resolves. That is how a native datasource behaves too: it joins the table
      # without applying the scopes of the collection mapped to it.
      def foreign_collection(relation)
        datasource.get_collection(relation.foreign_collection)
      end

      # Either a name this collection carries no relation under -- a condition
      # from a scope or a segment written against another schema -- or a
      # many-to-many, which is published unfilterable: resolving one would mean
      # reading the collection it travels through once per value.
      def refuse_unknown_relation!(leaf, relation_name)
        filterable = fields.select { |_, field| field.is_a?(ManyToOneSchema) }.keys

        raise UnsupportedOperatorError,
              "#{name} cannot filter #{leaf.field.inspect}: #{relation_name.inspect} is not a relation it filters " \
              "through. #{filterable.empty? ? "It has none." : "Those it does: #{filterable.join(", ")}."} Filter " \
              'on a column of the collection next door instead.'
      end

      # Two hops would mean resolving a relation of a relation, one read per
      # level, and nothing in this datasource publishes a filter that deep -- a
      # many-to-many is published unfilterable. It is refused by name rather than
      # half-answered.
      def refuse_two_hops!(leaf)
        raise UnsupportedOperatorError,
              "#{name} cannot filter #{leaf.field.inspect}: it reaches through two relations, and this datasource " \
              'resolves one. Filter on a column of the collection next door instead.'
      end
    end
  end
end
