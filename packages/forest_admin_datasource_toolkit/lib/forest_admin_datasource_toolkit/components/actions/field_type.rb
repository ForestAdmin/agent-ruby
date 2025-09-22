module ForestAdminDatasourceToolkit
  module Components
    module Actions
      class FieldType
        BOOLEAN = 'Boolean'.freeze

        DATE = 'Date'.freeze

        TIME = 'Time'.freeze

        DATE_ONLY = 'Dateonly'.freeze

        COLLECTION = 'Collection'.freeze

        ENUM = 'Enum'.freeze

        ENUM_LIST = 'EnumList'.freeze

        FILE = 'File'.freeze

        FILE_LIST = 'FileList'.freeze

        JSON = 'Json'.freeze

        NUMBER = 'Number'.freeze

        NUMBER_LIST = 'NumberList'.freeze

        STRING = 'String'.freeze

        STRING_LIST = 'StringList'.freeze

        LAYOUT = 'Layout'.freeze

        def self.all
          constants.map { |constant| const_get(constant) }
        end
      end
    end
  end
end
