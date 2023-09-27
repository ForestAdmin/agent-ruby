require 'spec_helper'

module ForestAdminDatasourceActiveRecord
  module Parser
    describe Relation do
      let(:dummy_class) { Class.new { extend Relation } }

      describe 'associations' do
        it 'fetch belongs_to relation' do
          associations = dummy_class.associations(Car)
          association = associations.select { |a| a.macro == :belongs_to }

          expect(association).not_to be_nil
        end

        it 'fetch belongs_to relation' do
          associations = dummy_class.associations(Car)
          association = associations.select { |a| a.macro == :has_one }

          expect(association).not_to be_nil
        end

        it 'fetch has_many relation' do
          associations = dummy_class.associations(Car)
          association = associations.select { |a| a.macro == :has_many }

          expect(association).not_to be_nil
        end

        it 'fetch many_to_many relation defined with has_many through' do
          associations = dummy_class.associations(Car)
          association = associations.select { |a| a.macro == :has_many && a.through_reflection? }

          expect(association).not_to be_nil
        end

        it 'not fetch polymorphic relation' do
          associations = dummy_class.associations(Car)
          association = associations.select { |a| a.options[:polymorphic] }

          expect(association).to be_empty
        end
      end
    end
  end
end
