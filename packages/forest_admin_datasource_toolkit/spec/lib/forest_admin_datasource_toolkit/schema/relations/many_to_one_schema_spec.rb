require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Schema
    module Relations
      describe ManyToOneSchema do
        subject(:relation) do
          described_class.new(
            foreign_key: 'foreign_key',
            foreign_key_target: 'foreign_key_target',
            foreign_collection: 'foreign_collection'
          )
        end

        describe 'getters' do
          it { expect(relation.type).to eq 'ManyToOne' }
          it { expect(relation.foreign_key).to eq 'foreign_key' }
          it { expect(relation.foreign_key_target).to eq 'foreign_key_target' }
          it { expect(relation.foreign_collection).to eq 'foreign_collection' }
        end

        describe 'setters' do
          before do
            relation.foreign_key = 'new_foreign_key'
            relation.foreign_collection = 'new_foreign_collection'
          end

          it { expect(relation.foreign_key).to eq 'new_foreign_key' }
          it { expect(relation.foreign_collection).to eq 'new_foreign_collection' }
        end
      end
    end
  end
end
