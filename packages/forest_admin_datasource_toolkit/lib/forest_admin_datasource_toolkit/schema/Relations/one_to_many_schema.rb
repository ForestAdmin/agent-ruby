module ForestAdminDatasourceToolkit
  module Schema
    module Relations
      class OneToManySchema < SingleRelationSchema
        def initialize(origin_key, origin_key_target, foreign_collection)
          super(origin_key, origin_key_target, foreign_collection, 'OneToMany')
          @origin_key = origin_key
          @origin_key_target = origin_key_target
        end
      end
    end
  end
end
