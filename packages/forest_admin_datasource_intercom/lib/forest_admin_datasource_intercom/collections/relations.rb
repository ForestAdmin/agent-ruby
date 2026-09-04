module ForestAdminDatasourceIntercom
  module Collections
    # How this datasource declares a relation, and how it answers one.
    #
    # Intercom joins nothing: a ticket carries an assignee id, and the teammate
    # behind it is a second read of a second endpoint. What makes that affordable
    # -- and exact -- is that every collection on the far end of these relations
    # is read whole in one request, the tier `FetchAllCollection` serves.
    #
    # Declaring a relation obliges both halves below, and the second is not
    # optional: a many-to-one is published filterable as soon as *any* column of
    # its target is (`GeneratorField#build_many_to_one_schema`), so the interface
    # offers `assignee:name` the moment the relation exists. Left unanswered,
    # that filter reaches a translator refusing every traversing field -- the
    # interface offering a filter the datasource then refuses, which is the one
    # thing this package is built not to do.
    #
    # * a projection through a relation (`assignee:name`) is answered by reading
    #   the target once per page and nesting its row under the relation name;
    # * a filter through a relation is answered by asking the target which of its
    #   records match, and filtering Intercom on the ids it names.
    #
    # The second is exact rather than approximate -- the target answers over
    # every record it holds, not over a page -- with one semantic worth stating
    # plainly: a row whose foreign key is null matches no relation filter, the
    # way a join drops it, negated filters included. A ticket with no assignee is
    # not "assigned to someone other than Marie".
    module Relations # rubocop:disable Metrics/ModuleLength
      ManyToOneSchema = ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema
      ManyToManySchema = ForestAdminDatasourceToolkit::Schema::Relations::ManyToManySchema
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
      def add_many_to_one(name, foreign_collection:, foreign_key:)
        add_field(name, ManyToOneSchema.new(foreign_collection: foreign_collection,
                                            foreign_key: foreign_key,
                                            foreign_key_target: 'id',
                                            is_read_only: true))
      end

      def add_many_to_many(name, foreign_collection:, through_collection:, origin_key:, foreign_key:)
        add_field(name, ManyToManySchema.new(foreign_collection: foreign_collection,
                                             through_collection: through_collection,
                                             origin_key: origin_key, origin_key_target: 'id',
                                             foreign_key: foreign_key, foreign_key_target: 'id',
                                             is_read_only: true))
      end

      # The rows of one page, with the relations the projection named nested onto
      # them. `records` are the same rows before projection: that is where the
      # foreign keys are read, since a projection naming `assignee:name` does not
      # have to name `admin_assignee_id`.
      #
      # One request per target *collection* per page -- never one per row, and
      # never twice for two relations that point at the same collection: a
      # ticket's `state` and `previous_state` are one read of `/ticket_states`,
      # over the ids both of them name.
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

      # The tree this tier can filter on, every `relation:field` leaf traded for
      # a condition on the foreign key. The block is handed that key and the ids
      # the target matched, and answers the node the tier wants: an `in` where
      # the filtering is done in memory, a group of equalities where Intercom's
      # DSL takes no membership operator.
      #
      # An `and` carrying a leaf that matches nothing matches nothing itself; an
      # `or` drops that leaf and keeps its siblings.
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
        relations_asked(projection).filter_map do |name, sub_projection|
          relation = fields[name]
          next unless relation.is_a?(ManyToOneSchema)

          [name, relation, Array(sub_projection).map(&:to_s).union([relation.foreign_key_target])]
        end
      end

      def indexed_targets(caller, records, asked)
        asked.group_by { |_, relation, _| relation.foreign_collection }
             .transform_values { |group| target_rows(caller, records, group) }
      end

      # One read per target collection, over the ids every relation pointing at
      # it names and the union of the columns they asked for.
      def target_rows(caller, records, group)
        relation = group.first[1]
        ids = group.flat_map { |_, rel, _| records.filter_map { |record| record[rel.foreign_key] } }.uniq
        return {} if ids.empty?

        target = relation.foreign_key_target
        wanted = Projection.new(group.flat_map { |_, _, columns| columns }.uniq)
        filter = Filter.new(condition_tree: Leaf.new(target, Operators::IN, ids))

        foreign_collection(relation).list(caller, filter, wanted).to_h { |row| [row[target], row] }
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

      # A relation group aggregating the way its parent does is inlined into it:
      # `or(x, or(a, b))` is `or(x, a, b)` and one level shallower. The level it
      # saves is one nothing budgeted for -- what a tier measured its nesting
      # limit against is the tree the operator wrote, not the equalities a
      # relation expands into afterwards.
      #
      # Only a relation group is inlined. A group the operator wrote is what
      # their filter means, and flattening it would spend on one group the
      # conditions two groups were holding.
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

      # Hook for a tier that cannot filter on every foreign key it declares a
      # relation on. Answered before the target is read: a refusal that spends a
      # request first costs exactly what it refuses to do.
      def check_relation_filterable!(_leaf, _relation); end

      # Which records of the target the condition names, asked of the target
      # itself: it owns what its columns can be filtered with, and it answers
      # over every record Intercom holds rather than over a page of them.
      def matching_ids(caller, relation, leaf)
        target = relation.foreign_key_target

        foreign_collection(relation)
          .list(caller, Filter.new(condition_tree: leaf), Projection.new([target]))
          .filter_map { |row| row[target] }
          .uniq
      end

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
