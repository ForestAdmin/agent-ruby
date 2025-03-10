require 'spec_helper'

module ForestAdminDatasourceMongoid
  module Utils
    module Pipeline
      include ForestAdminDatasourceToolkit::Components::Query
      describe GroupGenerator do
        it 'creates a pipeline for sum (w/o field nor group)' do
          aggregation = Aggregation.new(operation: 'Sum', field: 'price')

          expect(described_class.group(aggregation)).to eq([
                                                             { '$group' => { _id: nil, value: { '$sum' => '$price' } } },
                                                             { '$project' => { '_id' => 0, 'group' => { '$literal' => {} }, 'value' => '$value' } }
                                                           ])
        end

        it 'creates a pipeline for count (w/o field nor group)' do
          aggregation = Aggregation.new(operation: 'Count')

          expect(described_class.group(aggregation)).to eq([
                                                             { '$group' => { _id: nil, value: { '$sum' => 1 } } },
                                                             { '$project' => { '_id' => 0, 'group' => { '$literal' => {} }, 'value' => '$value' } }
                                                           ])
        end

        it 'creates a pipeline for count (w/ field)' do
          aggregation = Aggregation.new(operation: 'Count', field: 'title')

          expect(described_class.group(aggregation)).to eq([
                                                             { '$group' => { _id: nil, value: { '$sum' => { '$cond' => [{ '$ne' => ['$title', nil] }, 1, 0] } } } },
                                                             { '$project' => { '_id' => 0, 'group' => { '$literal' => {} }, 'value' => '$value' } }
                                                           ])
        end

        it 'creates a pipeline for count (w/ groups)' do
          aggregation = Aggregation.new(operation: 'Count', groups: [{ field: 'title' }])

          expect(described_class.group(aggregation)).to eq([
                                                             { '$group' => { _id: { 'title' => '$title' }, value: { '$sum' => 1 } } },
                                                             { '$project' => { '_id' => 0, 'group' => { 'title' => '$_id.title' }, 'value' => '$value' } }
                                                           ])
        end

        it 'creates a pipeline for count (w/ groups by month)' do
          aggregation = Aggregation.new(operation: 'Count', groups: [{ field: 'createdAt', operation: 'Month' }])

          expect(described_class.group(aggregation)).to eq([
                                                             {
                                                               '$group' => {
                                                                 _id: { 'createdAt' => { '$dateToString' => { 'date' => '$createdAt', 'format' => '%Y-%m-01' } } },
                                                                 value: { '$sum' => 1 }
                                                               }
                                                             },
                                                             { '$project' => { '_id' => 0, 'group' => { 'createdAt' => '$_id.createdAt' }, 'value' => '$value' } }
                                                           ])
        end

        it 'creates a pipeline for count (w/ groups by week)' do
          aggregation = Aggregation.new(operation: 'Count', groups: [{ field: 'createdAt', operation: 'Week' }])

          expect(described_class.group(aggregation)).to eq([
                                                             {
                                                               '$group' => {
                                                                 _id: {
                                                                   'createdAt' => {
                                                                     '$dateToString' => {
                                                                       'date' => { '$dateTrunc' => { 'date' => '$createdAt', 'startOfWeek' => 'Monday', 'unit' => 'week' } },
                                                                       'format' => '%Y-%m-%d'
                                                                     }
                                                                   }
                                                                 },
                                                                 value: { '$sum' => 1 }
                                                               }
                                                             },
                                                             { '$project' => { '_id' => 0, 'group' => { 'createdAt' => '$_id.createdAt' }, 'value' => '$value' } }
                                                           ])
        end
      end
    end
  end
end
