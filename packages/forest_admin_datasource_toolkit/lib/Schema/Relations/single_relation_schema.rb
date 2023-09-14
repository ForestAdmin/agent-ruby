module ForestAdminDatasourceToolkit
  module Schema
    module Relations
      class SingleRelationSchema < RelationSchema
        self.abstract_class = true

        attr_accessor :origin_key
        attr_reader :origin_key_target

        def initialize(origin_key, origin_key_target, foreign_collection, type)
          super(foreign_collection, type)
          @origin_key = origin_key
          @origin_key_target = origin_key_target
        end
      end
    end
  end
end
