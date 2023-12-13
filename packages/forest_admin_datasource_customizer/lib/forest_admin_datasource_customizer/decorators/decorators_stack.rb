module ForestAdminDatasourceCustomizer
  module Decorators
    class DecoratorsStack
      attr_reader :datasource

      def initialize(datasource)
        last = datasource
        @datasource = last
      end
    end
  end
end
