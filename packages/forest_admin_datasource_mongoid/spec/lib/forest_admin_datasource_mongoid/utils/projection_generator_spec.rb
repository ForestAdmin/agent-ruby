require 'spec_helper'

module ForestAdminDatasourceMongoid
  module Utils
    module Pipeline
      include ForestAdminDatasourceToolkit::Components::Query
      describe ProjectionGenerator do
        it 'generates a $replaceRoot stage when no fields are provided' do
          pipeline = described_class.project(Projection.new)

          expect(pipeline).to eq([{ '$replaceRoot' => { 'newRoot' => { '$literal' => {} } } }])
        end

        it 'generates a $project stage when fields are provided' do
          pipeline = described_class.project(Projection.new(['title:_id']))

          expect(pipeline).to eq([{ '$project' => { '_id' => false, 'title._id' => true, 'FOREST_RECORD_DOES_NOT_EXIST' => true } }])
        end
      end
    end
  end
end
