module ForestAdminDatasourceToolkit
  module Schema
    module Relations
      class ManyToOneSchema < RelationSchema
        attr_accessor :foreign_key, :foreign_key_target, :is_filterable

        def initialize(foreign_key:, foreign_key_target:, foreign_collection:, is_read_only: false, is_filterable: true)
          super(foreign_collection, 'ManyToOne', is_read_only: is_read_only)
          @is_filterable = is_filterable
          @foreign_key = foreign_key
          @foreign_key_target = foreign_key_target
        end
      end
    end
  end
end
