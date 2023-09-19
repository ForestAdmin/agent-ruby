module ForestAdminDatasourceToolkit
  module Schema
    module Relations
      class OneToOneSchema < SingleRelationSchema
        def initialize(origin_key, origin_key_target, foreign_collection)
          super(origin_key, origin_key_target, foreign_collection, 'OneToOne')
          @origin_key = origin_key
          @origin_key_target = origin_key_target
        end
      end
    end
  end
end
