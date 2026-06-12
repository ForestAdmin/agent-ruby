module ForestAdminDatasourceMambuPayments
  module Plugins
    module Relations
      # Base for the "simple" reciprocal OneToMany links: the target already
      # carries a native foreign key, so the plugin only declares the relation
      # on the host. Subclasses configure it declaratively:
      #
      #   class LinkExternalAccountToIncomingPayments < OneToManyLinkPlugin
      #     link host: 'MambuExternalAccount', to: 'MambuIncomingPayment',
      #          name: 'incoming_payments', origin_key: 'external_account_id'
      #   end
      #
      # Install at the datasource level: @agent.use(plugin, {}).
      class OneToManyLinkPlugin < ForestAdminDatasourceCustomizer::Plugins::Plugin
        class << self
          attr_reader :config
        end

        def self.link(host:, to:, name:, origin_key:)
          @config = { host: host, to: to, name: name, origin_key: origin_key }
        end

        def run(datasource_customizer, _collection_customizer = nil, _options = {})
          Plugins::Helpers.require_datasource!(datasource_customizer, self.class)

          cfg = self.class.config
          datasource_customizer.customize_collection(cfg[:host]) do |c|
            c.add_one_to_many_relation(cfg[:name], cfg[:to],
                                       origin_key: cfg[:origin_key], origin_key_target: 'id')
          end
        end
      end
    end
  end
end
