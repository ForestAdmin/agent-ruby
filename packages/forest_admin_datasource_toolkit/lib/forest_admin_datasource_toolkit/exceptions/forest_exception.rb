module ForestAdminDatasourceToolkit
  module Exceptions
    class ForestException < RuntimeError
      def initialize(msg = '')
        msg = "🌳🌳🌳 #{msg}"
        super
      end
    end
  end
end
