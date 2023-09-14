module ForestAdminDatasourceToolkit
  module Exception
    class ForestException < RuntimeError
      def initialize(msg = '')
        msg = "🌳🌳🌳 #{msg}"
        super msg
      end
    end
  end
end
