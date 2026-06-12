module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # Base for AccountHolder links reached transitively through an account
      # relation. The `host` imports `account_holder_id` from a related account,
      # exposes a ManyToOne to AccountHolder, and gets a TwoStepHolderFilter
      # (which rewrites holder filters onto `local_fk`); AccountHolder gets the
      # reciprocal OneToMany. Subclasses configure it declaratively:
      #
      #   class LinkAccountHolderToIncomingPayments < HolderLinkPlugin
      #     link host: 'MambuIncomingPayment', name: 'incoming_payments',
      #          local_fk: 'internal_account_id', intermediate: 'MambuInternalAccount',
      #          import_path: 'internal_account:account_holder_id'
      #   end
      #
      # Install at the datasource level: @agent.use(plugin, {}).
      class HolderLinkPlugin < ForestAdminDatasourceCustomizer::Plugins::Plugin
        ACCOUNT_HOLDER = 'MambuAccountHolder'.freeze
        FK_NAME = 'account_holder_id'.freeze

        class << self
          attr_reader :config
        end

        # rubocop:disable Metrics/ParameterLists
        def self.link(host:, name:, local_fk:, intermediate:, import_path:, many_to_one_name: 'account_holder')
          @config = {
            host: host, name: name, local_fk: local_fk, intermediate: intermediate,
            import_path: import_path, many_to_one_name: many_to_one_name
          }
        end
        # rubocop:enable Metrics/ParameterLists

        def run(datasource_customizer, _collection_customizer = nil, _options = {})
          Plugins::Helpers.require_datasource!(datasource_customizer, self.class)

          cfg = self.class.config
          datasource_customizer.customize_collection(cfg[:host]) do |c|
            c.import_field(FK_NAME, path: cfg[:import_path], readonly: true)
            c.add_many_to_one_relation(cfg[:many_to_one_name], ACCOUNT_HOLDER,
                                       foreign_key: FK_NAME, foreign_key_target: 'id')
            TwoStepHolderFilter.install(c,
                                        fk_name: FK_NAME,
                                        local_fk: cfg[:local_fk],
                                        intermediate_collection: cfg[:intermediate])
          end

          datasource_customizer.customize_collection(ACCOUNT_HOLDER) do |c|
            c.add_one_to_many_relation(cfg[:name], cfg[:host],
                                       origin_key: FK_NAME, origin_key_target: 'id')
          end
        end
      end
    end
  end
end
