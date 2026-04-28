module ForestAdminDatasourceToolkit
  module Schema
    module Relations
      class PolymorphicOneToManySchema < RelationSchema
        attr_accessor :origin_key, :origin_type_value
        attr_reader :origin_key_target, :origin_type_field, :cascade_on_delete

        def initialize(origin_key:, origin_key_target:, foreign_collection:, origin_type_field:, origin_type_value:,
                       cascade_on_delete: false)
          super(foreign_collection, 'PolymorphicOneToMany')
          @origin_key = origin_key
          @origin_key_target = origin_key_target
          @origin_type_field = origin_type_field
          @origin_type_value = origin_type_value
          @cascade_on_delete = cascade_on_delete
        end
      end
    end
  end
end
