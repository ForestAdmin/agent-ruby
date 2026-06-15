module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # Base for relations whose foreign key is not native: the `filtered`
      # collection gets a virtual (always-nil) FK column plus a two-step
      # operator filter that rewrites EQUAL/IN predicates, and the `owner`
      # collection gets the reciprocal OneToMany. Subclasses declare the shape
      # and provide the concrete filter install:
      #
      #   class LinkInternalAccountToBalances < TwoStepLinkPlugin
      #     link owner: 'MambuInternalAccount', filtered: 'MambuBalance',
      #          name: 'balances', fk: 'internal_account_id'
      #     def install_source_filter(collection)
      #       TwoStepConnectedAccountFilter.install(collection, target_field: 'connected_account_id')
      #     end
      #   end
      #
      # Install at the datasource level: @agent.use(plugin, {}).
      class TwoStepLinkPlugin < ForestAdminDatasourceCustomizer::Plugins::Plugin
        ComputedDefinition = ForestAdminDatasourceCustomizer::Decorators::Computed::ComputedDefinition

        class << self
          attr_reader :config
        end

        def self.link(owner:, filtered:, name:, foreign_key:)
          @config = { owner: owner, filtered: filtered, name: name, fk: foreign_key }
        end

        # The virtual FK is nil per record: a reverse lookup would require
        # scanning the pivot/intermediate collection. Only EQUAL/IN filters are
        # meaningful, and those are rewritten by the source filter.
        def self.virtual_fk
          ComputedDefinition.new(
            column_type: 'String',
            dependencies: ['id'],
            values: proc { |records, _ctx| records.map { nil } }
          )
        end

        def run(datasource_customizer, _collection_customizer = nil, _options = {})
          Plugins::Helpers.require_datasource!(datasource_customizer, self.class)

          cfg = self.class.config
          plugin = self
          datasource_customizer.customize_collection(cfg[:filtered]) do |c|
            c.add_field(cfg[:fk], TwoStepLinkPlugin.virtual_fk)
            plugin.install_source_filter(c)
          end

          datasource_customizer.customize_collection(cfg[:owner]) do |c|
            c.add_one_to_many_relation(cfg[:name], cfg[:filtered],
                                       origin_key: cfg[:fk], origin_key_target: 'id')
          end
        end

        # Installs the operator filter that rewrites the virtual FK predicate.
        def install_source_filter(_collection)
          raise NotImplementedError, "#{self.class} must implement #install_source_filter"
        end
      end
    end
  end
end
