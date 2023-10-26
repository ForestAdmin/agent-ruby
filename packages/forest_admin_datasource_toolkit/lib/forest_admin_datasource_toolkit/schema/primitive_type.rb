module ForestAdminDatasourceToolkit
  module Schema
    class PrimitiveType
      BINARY = 'Binary'.freeze

      BOOLEAN = 'Boolean'.freeze

      DATE = 'Date'.freeze

      DATEONLY = 'Dateonly'.freeze

      ENUM = 'Enum'.freeze

      JSON = 'Json'.freeze

      NUMBER = 'Number'.freeze

      POINT = 'Point'.freeze

      STRING = 'String'.freeze

      TIMEONLY = 'Timeonly'.freeze

      UUID = 'Uuid'.freeze

      def self.all
        constants
      end
    end
  end
end
