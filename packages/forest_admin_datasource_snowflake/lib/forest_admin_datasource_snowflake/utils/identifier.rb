module ForestAdminDatasourceSnowflake
  module Utils
    module Identifier
      module_function

      def quote(name)
        s = name.to_s
        return s if s == '*'

        %("#{s.gsub('"', '""')}")
      end
    end
  end
end
