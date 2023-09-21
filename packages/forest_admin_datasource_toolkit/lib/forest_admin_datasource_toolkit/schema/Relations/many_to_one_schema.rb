module ForestAdminDatasourceToolkit
  module Schema
    module Relations
      class ManyToOneSchema < RelationSchema
        attr_accessor :foreign_key
        attr_reader :foreign_key_target

        def initialize(foreign_key:, foreign_key_target:, foreign_collection:)
          super(foreign_collection, 'ManyToOne')
          @foreign_key = foreign_key
          @foreign_key_target = foreign_key_target
        end
      end
    end
  end
end
