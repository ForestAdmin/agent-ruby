module ForestAdminDatasourceMongoid
  module Utils
    class VersionManager
      def self.sub_document?(field)
        field.is_a?(Mongoid::Association::Embedded::EmbedsOne)
      end

      def self.sub_document_array?(field)
        field.is_a?(Mongoid::Association::Embedded::EmbedsMany)
      end
    end
  end
end
