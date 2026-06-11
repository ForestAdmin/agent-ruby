module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # Shared machinery for the "two-step" relation filters. Forest's native
      # OneToMany navigation emits a leaf on a virtual foreign key; these filters
      # pre-resolve that key against an intermediate collection and rewrite the
      # predicate as `target_field IN [resolved ids]`.
      #
      # Centralising it here keeps the four concrete filters in sync: the
      # match-nothing sentinel, the EQUAL/IN normalisation, and — crucially —
      # the *paginated* intermediate read all live in one place. A single
      # un-paginated `list` would silently cap resolution at one API page and
      # drop matching records for large relations.
      module PivotResolution
        Operators           = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators
        ConditionTreeLeaf   = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf
        ConditionTreeBranch = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeBranch
        Filter              = ForestAdminDatasourceToolkit::Components::Query::Filter
        Projection          = ForestAdminDatasourceToolkit::Components::Query::Projection
        Page                = ForestAdminDatasourceToolkit::Components::Query::Page

        # All-zero UUID: guaranteed not to exist in Numeral, so the native list
        # returns []. Expresses "match nothing" without tripping the empty-IN
        # guard in ConditionTreeTranslator.
        NO_MATCH_SENTINEL = '00000000-0000-0000-0000-000000000000'.freeze

        # Only EQUAL/IN are rewritten — the operators Forest's OneToMany
        # navigation actually emits.
        SUPPORTED_OPS = [Operators::EQUAL, Operators::IN].freeze

        PAGE_SIZE = 100

        module_function

        def normalize(value, operator)
          values = operator == Operators::IN ? Array(value) : [value]
          values.compact.reject { |v| v.to_s.empty? }.uniq
        end

        def no_match(target_field)
          ConditionTreeLeaf.new(target_field, Operators::EQUAL, NO_MATCH_SENTINEL)
        end

        def and_branch(*leaves)
          ConditionTreeBranch.new('And', leaves)
        end

        # Lists every row of `collection_name` matching `condition_tree`, paging
        # until the result is exhausted, and returns the unique non-empty values
        # of `field` (handles both scalar columns and array columns such as
        # InternalAccount.connected_account_ids).
        def collect(context, collection_name, condition_tree, field)
          collection = context.datasource.get_collection(collection_name)
          offset = 0
          values = []
          loop do
            rows = collection.list(
              Filter.new(condition_tree: condition_tree, page: Page.new(offset: offset, limit: PAGE_SIZE)),
              Projection.new([field])
            )
            values.concat(rows.flat_map { |row| Array(row[field]) })
            break if rows.size < PAGE_SIZE

            offset += PAGE_SIZE
          end
          values.compact.reject { |v| v.to_s.empty? }.uniq
        end
      end
    end
  end
end
