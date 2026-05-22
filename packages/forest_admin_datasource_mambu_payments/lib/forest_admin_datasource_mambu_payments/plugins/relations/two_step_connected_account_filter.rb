module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # Two-step pre-resolution for `internal_account_id` filters on host
      # collections that link to InternalAccount transitively via the array
      # column `InternalAccount.connected_account_ids` (not a scalar FK).
      # Resolves the holder ids to the set of connected_account ids, then
      # rewrites the predicate against a real field on the host collection
      # (`id` for ConnectedAccount, `connected_account_id` for resources
      # scoped by connected account). Only EQUAL/IN are handled (the
      # operators Forest's OneToMany navigation actually uses).
      module TwoStepConnectedAccountFilter
        Operators         = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Operators
        ConditionTreeLeaf = ForestAdminDatasourceToolkit::Components::Query::ConditionTree::Nodes::ConditionTreeLeaf
        Filter            = ForestAdminDatasourceToolkit::Components::Query::Filter
        Projection        = ForestAdminDatasourceToolkit::Components::Query::Projection

        INTERNAL_ACCOUNT = 'MambuInternalAccount'.freeze
        ARRAY_FIELD      = 'connected_account_ids'.freeze
        FK_NAME          = 'internal_account_id'.freeze

        # See TwoStepHolderFilter::NO_MATCH_SENTINEL for the rationale.
        NO_MATCH_SENTINEL = '00000000-0000-0000-0000-000000000000'.freeze

        SUPPORTED_OPS = [Operators::EQUAL, Operators::IN].freeze

        def self.install(collection_customizer, target_field:)
          SUPPORTED_OPS.each do |operator|
            collection_customizer.replace_field_operator(FK_NAME, operator) do |value, context|
              ia_ids = TwoStepConnectedAccountFilter.normalize(value, operator)
              next TwoStepConnectedAccountFilter.no_match(target_field) if ia_ids.empty?

              ca_ids = context.datasource.get_collection(INTERNAL_ACCOUNT).list(
                Filter.new(condition_tree: ConditionTreeLeaf.new('id', Operators::IN, ia_ids)),
                Projection.new([ARRAY_FIELD])
              ).flat_map { |r| Array(r[ARRAY_FIELD]) }.compact.uniq

              next TwoStepConnectedAccountFilter.no_match(target_field) if ca_ids.empty?

              ConditionTreeLeaf.new(target_field, Operators::IN, ca_ids)
            end
          end
        end

        def self.normalize(value, operator)
          values = operator == Operators::IN ? Array(value) : [value]
          values.compact.reject { |v| v.to_s.empty? }.uniq
        end

        def self.no_match(target_field)
          ConditionTreeLeaf.new(target_field, Operators::EQUAL, NO_MATCH_SENTINEL)
        end
      end
    end
  end
end
