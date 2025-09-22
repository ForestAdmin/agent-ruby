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
              ['romain', Flattener::Undefined.new, 'ana']
            ]
            projection = Projection.new(%w[id book:author:firstname])

            expect(described_class.un_flatten(flat_list, projection)).to eq(
              [
                { 'id' => 1, 'book' => { 'author' => { 'firstname' => 'romain' } } },
                { 'id' => 2 },
                { 'id' => 3, 'book' => { 'author' => { 'firstname' => 'ana' } } }
              ]
            )
          end

          it 'unflatten() should work with multiple undefined' do
            flat_list = [
              [Flattener::Undefined.new],
              [15],
              [26],
              [Flattener::Undefined.new]
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

          describe 'flatten' do
            it 'works with simple case' do
              records = [
                { 'id' => 1, 'book' => { 'author' => { 'firstname' => 'romain' } } },
                { 'id' => 2, 'book' => nil },
                { 'id' => 3, 'book' => { 'author' => { 'firstname' => 'ana' } } }
              ]
              projection = Projection.new(%w[id book:author:firstname])

              expect(described_class.flatten(records, projection)).to contain_exactly(
                contain_exactly(1, 2, 3),
                contain_exactly('romain', an_instance_of(Flattener::Undefined), 'ana')
              )
            end

            it 'round trip with markers should conserve null values' do
              records = [
                { 'id' => 1 },
                { 'id' => 2, 'book' => nil },
                { 'id' => 3, 'book' => { 'author' => nil } },
                { 'id' => 4, 'book' => { 'author' => { 'firstname' => 'Isaac', 'lastname' => 'Asimov' } } },
                { 'id' => 5, 'book' => { 'author' => { 'firstname' => nil, 'lastname' => nil } } }
              ]

              projection = Projection.new(%w[id book:author:firstname book:author:lastname])
              projection_with_marker = described_class.with_null_marker(projection)
              flattened = described_class.flatten(records, projection_with_marker)
              unflattened = described_class.un_flatten(flattened, projection_with_marker)

              expect(projection_with_marker).to eq(
                %w[id book:author:firstname book:author:lastname book:__null_marker book:author:__null_marker]
              )

              expect(flattened).to contain_exactly(
                contain_exactly(1, 2, 3, 4, 5),
                contain_exactly(
                  an_instance_of(Flattener::Undefined),
                  an_instance_of(Flattener::Undefined),
                  an_instance_of(Flattener::Undefined),
                  'Isaac',
                  nil
                ),
                contain_exactly(
                  an_instance_of(Flattener::Undefined),
                  an_instance_of(Flattener::Undefined),
                  an_instance_of(Flattener::Undefined),
                  'Asimov',
                  nil
                ),
                contain_exactly(
                  an_instance_of(Flattener::Undefined),
                  nil,
                  an_instance_of(Flattener::Undefined),
                  an_instance_of(Flattener::Undefined),
                  an_instance_of(Flattener::Undefined)
                ),
                contain_exactly(
                  an_instance_of(Flattener::Undefined),
                  an_instance_of(Flattener::Undefined),
                  nil,
                  an_instance_of(Flattener::Undefined),
                  an_instance_of(Flattener::Undefined)
                )
              )

              expect(unflattened).to eq(records)
            end
          end
        end
      end
    end
  end
end
