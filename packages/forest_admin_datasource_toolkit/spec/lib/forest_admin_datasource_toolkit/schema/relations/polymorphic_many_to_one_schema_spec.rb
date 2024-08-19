require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Schema
    module Relations
      describe PolymorphicManyToOneSchema do
        subject(:relation) do
          described_class.new(
            foreign_key_type_field: 'foreign_key_type_field',
            foreign_collections: ['Foo'],
            foreign_key_targets: { 'Foo' => 'id' },
            foreign_key: 'foreign_key'
          )
        end

        describe 'getters' do
          it { expect(relation.type).to eq 'PolymorphicManyToOne' }
          it { expect(relation.foreign_key).to eq 'foreign_key' }
          it { expect(relation.foreign_key_type_field).to eq 'foreign_key_type_field' }
          it { expect(relation.foreign_key_targets).to eq({ 'Foo' => 'id' }) }
          it { expect(relation.foreign_collections).to eq ['Foo'] }
        end
      end
    end
  end
end
