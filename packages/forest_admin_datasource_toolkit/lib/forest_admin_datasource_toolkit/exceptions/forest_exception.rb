module ForestAdminDatasourceToolkit
  module Exceptions
    class ForestException < RuntimeError
      def initialize(msg = '')
        msg = "🌳🌳🌳 #{msg}"
        super(msg)
      end
    end
  end
end
