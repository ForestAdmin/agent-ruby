module ForestAdminDatasourceToolkit
  module Schema
    module Relations
      class PolymorphicOneToManySchema < RelationSchema
        attr_accessor :origin_key, :origin_type_value
        attr_reader :origin_key_target, :origin_type_field

        def initialize(origin_key:, origin_key_target:, foreign_collection:, origin_type_field:, origin_type_value:)
          super(foreign_collection, 'PolymorphicOneToMany')
          @origin_key = origin_key
          @origin_key_target = origin_key_target
          @origin_type_field = origin_type_field
          @origin_type_value = origin_type_value
        end
      end
    end
  end
end
