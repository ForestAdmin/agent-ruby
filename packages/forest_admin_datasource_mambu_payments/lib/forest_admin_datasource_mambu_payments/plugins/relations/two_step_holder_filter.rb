module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # Two-step pre-resolution for `account_holder_id` filters on host
      # collections that link to AccountHolder transitively. Default
      # `import_field` would emit a nested leaf the native list rejects;
      # we pre-list the intermediate collection and rewrite as
      # `local_fk IN (ids)`. Only EQUAL/IN are handled (the operators
      # Forest's OneToMany navigation actually uses).
      module TwoStepHolderFilter
        Operators         = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators
        ConditionTreeLeaf = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf
        Filter            = ForestAdminDatasourceToolkit::Components::Query::Filter
        Projection        = ForestAdminDatasourceToolkit::Components::Query::Projection

        # All-zero UUID: guaranteed not to exist in Numeral, so the native
        # list returns []. Used to express "match nothing" without tripping
        # the empty-IN guard in ConditionTreeTranslator.
        NO_MATCH_SENTINEL = '00000000-0000-0000-0000-000000000000'.freeze

        SUPPORTED_OPS = [Operators::EQUAL, Operators::IN].freeze

        def self.install(collection_customizer, fk_name:, local_fk:, intermediate_collection:)
          SUPPORTED_OPS.each do |operator|
            collection_customizer.replace_field_operator(fk_name, operator) do |value, context|
              holder_ids = TwoStepHolderFilter.normalize(value, operator)
              next TwoStepHolderFilter.no_match(local_fk) if holder_ids.empty?

              fk_ids = context.datasource.get_collection(intermediate_collection).list(
                Filter.new(condition_tree: ConditionTreeLeaf.new(fk_name, Operators::IN, holder_ids)),
                Projection.new(['id'])
              ).map { |r| r['id'] }.uniq

              next TwoStepHolderFilter.no_match(local_fk) if fk_ids.empty?

              ConditionTreeLeaf.new(local_fk, Operators::IN, fk_ids)
            end
          end
        end

        def self.normalize(value, operator)
          values = operator == Operators::IN ? Array(value) : [value]
          values.compact.reject { |v| v.to_s.empty? }.uniq
        end

        def self.no_match(local_fk)
          ConditionTreeLeaf.new(local_fk, Operators::EQUAL, NO_MATCH_SENTINEL)
        end
      end
    end
  end
end
