module ForestAdminDatasourceMongoid
  module Utils
    module Pipeline
      class ProjectionGenerator
        def self.project(projection)
          return [{ '$replaceRoot' => { 'newRoot' => { '$literal' => {} } } }] if projection.empty?

          project = { '_id' => false, 'FOREST_RECORD_DOES_NOT_EXIST' => true }

          projection.each do |field|
            formatted_field = field.tr(':', '.')
            project[formatted_field] = true
          end

          [{ '$project' => project }]
        end
      end
    end
  end
end
