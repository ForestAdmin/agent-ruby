module ForestAdminDatasourceToolkit
  module Exceptions
    class ValidationError < ForestException
      def initialize(msg = '')
        super
      end
    end
  end
end
