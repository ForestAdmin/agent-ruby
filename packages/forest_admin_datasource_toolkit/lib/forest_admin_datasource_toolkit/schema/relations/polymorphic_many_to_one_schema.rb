module ForestAdminDatasourceToolkit
  module Schema
    module Relations
      class PolymorphicManyToOneSchema
        attr_reader :foreign_key_target, :foreign_key, :foreign_key_targets, :foreign_key_type_field,
                    :foreign_collections, :type

        def initialize(
          foreign_key_type_field:,
          foreign_key:,
          foreign_key_targets:,
          foreign_collections:
        )
          @foreign_key = foreign_key
          @foreign_key_targets = foreign_key_targets
          @foreign_key_type_field = foreign_key_type_field
          @foreign_collections = foreign_collections
          @type = 'PolymorphicManyToOne'
        end
      end
    end
  end
end
