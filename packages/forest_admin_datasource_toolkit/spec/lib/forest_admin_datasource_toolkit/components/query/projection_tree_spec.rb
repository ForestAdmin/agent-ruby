require 'spec_helper'

module ForestAdminDatasourceToolkit
  module Components
    module Query
      describe ProjectionTree do
        subject(:tree) { described_class.build(Projection.new(%w[id name author:name author:address:city])) }

        it 'splits the columns and the relations recursively' do
          expect(tree.columns).to eq(%w[id name])
          expect(tree.relations.keys).to eq(['author'])
          expect(tree.relations['author'].columns).to eq(['name'])
          expect(tree.relations['author'].relations['address'].columns).to eq(['city'])
        end

        it 'is frozen, so it is unaffected by later mutations of the projection' do
          projection = Projection.new(%w[id author:name])
          snapshot = described_class.build(projection)
          projection.delete('author:name')

          expect([snapshot, snapshot.columns, snapshot.relations]).to all(be_frozen)
          expect(snapshot.relations.keys).to eq(['author'])
        end

        it 're_projects nil to nil' do
          expect(tree.re_project(nil)).to be_nil
        end
      end
    end
  end
end
