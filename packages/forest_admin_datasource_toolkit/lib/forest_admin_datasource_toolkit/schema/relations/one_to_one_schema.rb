module ForestAdminDatasourceToolkit
  module Schema
    module Relations
      class OneToOneSchema < RelationSchema
        attr_accessor :origin_key, :origin_key_target

        def initialize(origin_key:, origin_key_target:, foreign_collection:, is_read_only: false)
          super(foreign_collection, 'OneToOne', is_read_only: is_read_only)
          @origin_key = origin_key
          @origin_key_target = origin_key_target
        end
      end
    end
  end
end
