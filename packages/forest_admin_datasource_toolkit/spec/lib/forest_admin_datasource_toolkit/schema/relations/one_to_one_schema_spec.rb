require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Schema
    module Relations
      describe OneToOneSchema do
        subject(:relation) do
          described_class.new(
            origin_key: 'origin_key',
            origin_key_target: 'origin_key_target',
            foreign_collection: 'foreign_collection'
          )
        end

        describe 'getters' do
          it { expect(relation.type).to eq 'OneToOne' }
          it { expect(relation.origin_key).to eq 'origin_key' }
          it { expect(relation.origin_key_target).to eq 'origin_key_target' }
          it { expect(relation.foreign_collection).to eq 'foreign_collection' }
        end

        describe 'setters' do
          before do
            relation.origin_key = 'new_origin_key'
            relation.foreign_collection = 'new_foreign_collection'
          end

          it { expect(relation.origin_key).to eq 'new_origin_key' }
          it { expect(relation.foreign_collection).to eq 'new_foreign_collection' }
        end
      end
    end
  end
end
