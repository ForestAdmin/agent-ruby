require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Schema
    module Relations
      describe ManyToManySchema do
        subject(:relation) do
          described_class.new(
            foreign_key: 'foreign_key',
            foreign_key_target: 'foreign_key_target',
            foreign_collection: 'foreign_collection',
            through_collection: 'through_collection',
            origin_key: 'origin_key',
            origin_key_target: 'origin_key_target'
          )
        end

        describe 'getters' do
          it { expect(relation.type).to eq 'ManyToMany' }
          it { expect(relation.foreign_key).to eq 'foreign_key' }
          it { expect(relation.foreign_key_target).to eq 'foreign_key_target' }
          it { expect(relation.foreign_collection).to eq 'foreign_collection' }
          it { expect(relation.origin_key).to eq 'origin_key' }
          it { expect(relation.origin_key_target).to eq 'origin_key_target' }
          it { expect(relation.through_collection).to eq 'through_collection' }
        end

        describe 'setters' do
          before do
            relation.foreign_key = 'new_foreign_key'
            relation.origin_key = 'new_origin_key'
            relation.foreign_collection = 'new_foreign_collection'
            relation.through_collection = 'new_through_collection'
          end

          it { expect(relation.foreign_key).to eq 'new_foreign_key' }
          it { expect(relation.origin_key).to eq 'new_origin_key' }
          it { expect(relation.foreign_collection).to eq 'new_foreign_collection' }
          it { expect(relation.through_collection).to eq 'new_through_collection' }
        end
      end
    end
  end
end
