require 'spec_helper'

module ForestAdminDatasourceMongoid
  module Utils
    module Pipeline
      describe ConditionGenerator do
        describe '.tag_record_if_not_exist' do
          it 'returns a $cond with FOREST_RECORD_DOES_NOT_EXIST for missing field' do
            result = described_class.tag_record_if_not_exist('field', 'then_value')

            expect(result).to eq({
                                   '$cond' => {
                                     'if' => {
                                       '$and' => [
                                         { '$ne' => [{ '$type' => '$field' }, 'missing'] },
                                         { '$ne' => ['$field', nil] }
                                       ]
                                     },
                                     'then' => 'then_value',
                                     'else' => { 'FOREST_RECORD_DOES_NOT_EXIST' => true }
                                   }
                                 })
          end
        end

        describe '.tag_record_if_not_exist_by_value' do
          it 'returns a $cond with FOREST_RECORD_DOES_NOT_EXIST as value' do
            result = described_class.tag_record_if_not_exist_by_value('field', 'then_value')

            expect(result).to eq({
                                   '$cond' => {
                                     'if' => {
                                       '$and' => [
                                         { '$ne' => [{ '$type' => '$field' }, 'missing'] },
                                         { '$ne' => ['$field', nil] }
                                       ]
                                     },
                                     'then' => 'then_value',
                                     'else' => 'FOREST_RECORD_DOES_NOT_EXIST'
                                   }
                                 })
          end
        end

        describe '.if_missing' do
          it 'returns then_expr if field exists and is not nil' do
            result = described_class.if_missing('field', 'then_value', 'else_value')

            expect(result).to eq({
                                   '$cond' => {
                                     'if' => {
                                       '$and' => [
                                         { '$ne' => [{ '$type' => '$field' }, 'missing'] },
                                         { '$ne' => ['$field', nil] }
                                       ]
                                     },
                                     'then' => 'then_value',
                                     'else' => 'else_value'
                                   }
                                 })
          end
        end
      end
    end
  end
end
