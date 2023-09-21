module ForestAdminDatasourceToolkit
  module Schema
    module Relations
      class ManyToManySchema < RelationSchema
        attr_accessor :origin_key, :through_collection, :foreign_key
        attr_reader :origin_key_target, :foreign_key_target

        def initialize(
          origin_key:,
          origin_key_target:,
          foreign_key:,
          foreign_key_target:,
          foreign_collection:,
          through_collection:
        )
          super(foreign_collection, 'ManyToMany')
          @origin_key = origin_key
          @origin_key_target = origin_key_target
          @through_collection = through_collection
          @foreign_key = foreign_key
          @foreign_key_target = foreign_key_target
        end
      end
    end
  end
end
