module ForestAdminDatasourceToolkit
  module Schema
    module Relations
      class PolymorphicOneToOneSchema < RelationSchema
        attr_accessor :origin_key
        attr_reader :origin_key_target, :origin_type_field, :origin_type_value

        def initialize(origin_key:, origin_key_target:, foreign_collection:, origin_type_field:, origin_type_value:)
          super(foreign_collection, 'PolymorphicOneToOne')
          @origin_key = origin_key
          @origin_key_target = origin_key_target
          @origin_type_field = origin_type_field
          @origin_type_value = origin_type_value
        end
      end
    end
  end
end
