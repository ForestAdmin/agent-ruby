module ForestAdminDatasourceCustomizer
  module Plugins
    class Plugin
      def run(_datasource_customizer, _collection_customizer = nil, _options = [])
        raise NotImplementedError, "#{self.class} has not implemented method '#{__method__}'"
      end
    end
  end
end
