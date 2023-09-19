module ForestAdminDatasourceToolkit
  module Schema
    module Relations
      class ManyRelationSchema < RelationSchema
        self.abstract_class = true

        attr_accessor :foreign_key
        attr_reader :foreign_key_target

        def initialize(foreign_key, foreign_key_target, foreign_collection, type)
          super(foreign_collection, type)
          @foreign_key = foreign_key
          @foreign_key_target = foreign_key_target
        end
      end
    end
  end
end
