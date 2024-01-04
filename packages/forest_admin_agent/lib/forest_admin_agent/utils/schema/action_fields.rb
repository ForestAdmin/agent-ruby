module ForestAdminAgent
  module Utils
    module Schema
      class ActionFields
        def self.collection_field?(field)
          field&.type == 'Collection'
        end

        def self.enum_field?(field)
          field&.type == 'Enum'
        end

        def self.enum_list_field?(field)
          field&.type == 'EnumList'
        end

        def self.file_field?(field)
          field&.type == 'File'
        end

        def self.file_list_field?(field)
          field&.type == 'FileList'
        end
      end
    end
  end
end
