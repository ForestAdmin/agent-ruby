require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Schema
    module Relations
      describe PolymorphicOneToOneSchema do
        subject(:relation) do
          described_class.new(
            origin_key: 'origin_key',
            origin_key_target: 'origin_key_target',
            origin_type_field: 'origin_type_field',
            origin_type_value: 'origin_type_value',
            foreign_collection: 'foreign_collection'
          )
        end

        describe 'getters' do
          it { expect(relation.type).to eq 'PolymorphicOneToOne' }
          it { expect(relation.origin_key).to eq 'origin_key' }
          it { expect(relation.origin_key_target).to eq 'origin_key_target' }
          it { expect(relation.origin_type_field).to eq 'origin_type_field' }
          it { expect(relation.origin_type_value).to eq 'origin_type_value' }
          it { expect(relation.foreign_collection).to eq 'foreign_collection' }
        end
      end
    end
  end
end
