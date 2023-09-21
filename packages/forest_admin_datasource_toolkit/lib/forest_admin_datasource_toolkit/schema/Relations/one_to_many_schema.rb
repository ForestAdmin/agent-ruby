module ForestAdminDatasourceToolkit
  module Schema
    module Relations
      class OneToManySchema < RelationSchema
        attr_accessor :origin_key
        attr_reader :origin_key_target

        def initialize(origin_key:, origin_key_target:, foreign_collection:)
          super(foreign_collection, 'OneToMany')
          @origin_key = origin_key
          @origin_key_target = origin_key_target
        end
      end
    end
  end
end
