module ForestAdminDatasourceToolkit
  module Schema
    module Relations
      class ManyToManySchema < RelationSchema
        attr_accessor :origin_key, :through_collection, :foreign_key, :origin_key_target, :foreign_key_target,
                      :origin_type_field, :origin_type_value

        def initialize(
          origin_key:,
          origin_key_target:,
          foreign_key:,
          foreign_key_target:,
          foreign_collection:,
          through_collection:,
          origin_type_field: nil,
          origin_type_value: nil
        )
          super(foreign_collection, 'ManyToMany')
          @origin_key = origin_key
          @origin_key_target = origin_key_target
          @through_collection = through_collection
          @foreign_key = foreign_key
          @foreign_key_target = foreign_key_target
          @origin_type_field = origin_type_field
          @origin_type_value = origin_type_value
        end
      end
    end
  end
end
