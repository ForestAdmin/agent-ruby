require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Computed
      module Utils
        include ForestAdminDatasourceToolkit::Components::Query
        describe Flattener do
          it 'unflatten() should work with simple case' do
            flat_list = [
              [1, 2, 3],
              ['romain', nil, 'ana']
            ]
            projection = Projection.new(['id', 'book:author:firstname'])

            expect(described_class.un_flatten(flat_list, projection)).to eq(
              [
                { 'id' => 1, 'book' => { 'author' => { 'firstname' => 'romain' } } },
                { 'id' => 2 },
                { 'id' => 3, 'book' => { 'author' => { 'firstname' => 'ana' } } }
              ]
            )
          end

          it 'unflatten() should work with multiple null' do
            flat_list = [
              [nil],
              [15],
              [26],
              [nil]
            ]
            projection = Projection.new(
              %w[rental:customer:name rental:id rental:numberOfDays rental:customer:id]
            )

            expect(described_class.un_flatten(flat_list, projection)).to eq(
              [
                { 'rental' => { 'id' => 15, 'numberOfDays' => 26 } }
              ]
            )
          end

          # test('flatten() should work', function () {
          #     $records = [
          #         ['id' => 1, 'book' => ['author' => ['firstname' => 'romain']]],
          #         ['id' => 2, 'book' => null],
          #         ['id' => 3, 'book' => ['author' => ['firstname' => 'ana']]],
          #     ];
          #     $projection = new Projection(['id', 'book:author:firstname']);
          #
          #     expect(Flattener::flatten($records, $projection))->toEqual(
          #         [
          #             [1, 2, 3],
          #             ['romain', null, 'ana'],
          #         ]
          #     );
          # });
          it 'flatten() should work' do
            records = [
              { 'id' => 1, 'book' => { 'author' => { 'firstname' => 'romain' } } },
              { 'id' => 2, 'book' => nil },
              { 'id' => 3, 'book' => { 'author' => { 'firstname' => 'ana' } } }
            ]
            projection = Projection.new(['id', 'book:author:firstname'])

            expect(described_class.flatten(records, projection)).to eq(
              [
                [1, 2, 3],
                ['romain', nil, 'ana']
              ]
            )
          end
        end
      end
    end
  end
end
