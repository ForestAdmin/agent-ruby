require 'spec_helper'

module ForestAdminDatasourceActiveRecord
  module Utils
    describe ActiveRecordSerializer do
      subject(:serializer) { described_class.new(Account.new, {}) }

      describe '#target_model' do
        it 'resolves a belongs_to hop to its target model' do
          expect(serializer.target_model(['supplier'])).to eq(Supplier)
        end

        it 'resolves a has_one :through chain to the final target model' do
          expect(serializer.target_model(['order'])).to eq(Order)
        end

        it 'returns nil when a hop is not an association' do
          expect(serializer.target_model(['not_a_relation'])).to be_nil
        end
      end
    end
  end
end
