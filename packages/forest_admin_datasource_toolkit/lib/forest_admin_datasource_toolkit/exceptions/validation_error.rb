module ForestAdminDatasourceToolkit
  module Exceptions
    class ValidationError < ForestException
      attr_reader :name

      def initialize(message)
        @name = 'ValidationError'
        super
      end
    end
  end
end
