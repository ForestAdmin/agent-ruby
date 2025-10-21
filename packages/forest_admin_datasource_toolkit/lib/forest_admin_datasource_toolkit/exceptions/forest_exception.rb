module ForestAdminDatasourceToolkit
  module Exceptions
    class ForestException < RuntimeError
      def initialize(msg = '')
        super
      end
    end
  end
end
