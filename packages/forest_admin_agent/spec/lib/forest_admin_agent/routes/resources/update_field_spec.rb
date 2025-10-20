require 'spec_helper'
require 'singleton'

module ForestAdminAgent
  module Routes
    module Resources
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminDatasourceToolkit::Schema

      describe UpdateField do
        include_context 'with caller'
        subject(:update_field) { described_class.new }

        let(:args) do
          {
            headers: { 'HTTP_AUTHORIZATION' => bearer },
            params: {
              'collection_name' => 'book',
              'id' => '1',
              'field_name' => 'tags',
              'index' => '0',
              'timezone' => 'Europe/Paris',
              data: {
                attributes: {
                  'value' => 'updated-tag'
                }
              }
            }
          }
        end

        let(:permissions) { instance_double(ForestAdminAgent::Services::Permissions) }

        before do
          allow(ForestAdminAgent::Services::Permissions).to receive(:new).and_return(permissions)
          allow(permissions).to receive_messages(can?: true, get_scope: nil)
        end

        it 'adds the route forest_update_field' do
          update_field.setup_routes
          expect(update_field.routes.include?('forest_update_field')).to be true
          expect(update_field.routes.length).to eq 1
        end

        describe 'handle_request' do
          before do
            book_class = Struct.new(:id, :title, :tags, :scores, :metadata) do
              def respond_to?(arg)
                return false if arg == :each

                super
              end
            end
            stub_const('Book', book_class)
            @datasource = Datasource.new
            @collection = build_collection(
              name: 'book',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(
                    column_type: 'Number',
                    is_primary_key: true,
                    filter_operators: [Operators::IN, Operators::EQUAL]
                  ),
                  'title' => ColumnSchema.new(column_type: 'String'),
                  'tags' => ColumnSchema.new(column_type: '[String]'),
                  'scores' => ColumnSchema.new(column_type: '[Number]'),
                  'metadata' => ColumnSchema.new(column_type: '[Json]')
                }
              }
            )

            allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)
            @datasource.add_collection(@collection)
            ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(@datasource)
            ForestAdminAgent::Builder::AgentFactory.instance.build
          end

          context 'with valid string array update' do
            it 'updates the array element at specified index' do
              book = { 'id' => 1, 'title' => 'Test Book', 'tags' => ['old-tag', 'keep-tag'] }
              updated_book = { 'id' => 1, 'title' => 'Test Book', 'tags' => ['updated-tag', 'keep-tag'] }

              allow(@datasource.get_collection('book')).to receive(:list).and_return([book], [updated_book])
              allow(@datasource.get_collection('book')).to receive(:update).and_return(true)

              result = update_field.handle_request(args)

              expect(@datasource.get_collection('book')).to have_received(:update).with(
                anything,
                anything,
                { tags: ['updated-tag', 'keep-tag'] }
              )
              expect(result[:name]).to eq('book')
              expect(result[:content]['data']['attributes']['tags']).to eq(['updated-tag', 'keep-tag'])
            end
          end

          context 'with number array update' do
            let(:args_with_number) do
              args.merge(
                params: args[:params].merge(
                  'field_name' => 'scores',
                  data: { attributes: { 'value' => 99 } }
                )
              )
            end

            it 'updates numeric array element' do
              book = { 'id' => 1, 'scores' => [10, 20, 30] }
              updated_book = { 'id' => 1, 'scores' => [99, 20, 30] }

              allow(@datasource.get_collection('book')).to receive(:list).and_return([book], [updated_book])
              allow(@datasource.get_collection('book')).to receive(:update).and_return(true)

              result = update_field.handle_request(args_with_number)

              expect(@datasource.get_collection('book')).to have_received(:update).with(
                anything,
                anything,
                { scores: [99, 20, 30] }
              )
              expect(result[:content]['data']['attributes']['scores']).to eq([99, 20, 30])
            end
          end

          context 'with JSON array update' do
            let(:args_with_json) do
              args.merge(
                params: args[:params].merge(
                  'field_name' => 'metadata',
                  data: { attributes: { 'value' => { 'key' => 'new', 'value' => 123 } } }
                )
              )
            end

            it 'updates JSON object in array' do
              book = { 'id' => 1, 'metadata' => [{ 'key' => 'old' }, { 'key' => 'keep' }] }
              updated_book = { 'id' => 1, 'metadata' => [{ 'key' => 'new', 'value' => 123 }, { 'key' => 'keep' }] }

              allow(@datasource.get_collection('book')).to receive(:list).and_return([book], [updated_book])
              allow(@datasource.get_collection('book')).to receive(:update).and_return(true)

              result = update_field.handle_request(args_with_json)

              expect(@datasource.get_collection('book')).to have_received(:update).with(
                anything,
                anything,
                { metadata: [{ 'key' => 'new', 'value' => 123 }, { 'key' => 'keep' }] }
              )
            end
          end

          context 'with last element update' do
            let(:args_with_last_index) do
              args.merge(
                params: args[:params].merge('index' => '2')
              )
            end

            it 'updates last element in array' do
              book = { 'id' => 1, 'tags' => ['first', 'second', 'last'] }
              updated_book = { 'id' => 1, 'tags' => ['first', 'second', 'updated-tag'] }

              allow(@datasource.get_collection('book')).to receive(:list).and_return([book], [updated_book])
              allow(@datasource.get_collection('book')).to receive(:update).and_return(true)

              result = update_field.handle_request(args_with_last_index)

              expect(@datasource.get_collection('book')).to have_received(:update).with(
                anything,
                anything,
                { tags: ['first', 'second', 'updated-tag'] }
              )
            end
          end

          context 'with permission denied' do
            before do
              allow(permissions).to receive(:can?).with(:edit, @collection)
                                                   .and_raise(Http::Exceptions::ForbiddenError.new('Permission denied'))
            end

            it 'raises ForbiddenError' do
              expect { update_field.handle_request(args) }
                .to raise_error(Http::Exceptions::ForbiddenError)
            end
          end

          context 'with non-existent field' do
            let(:args_with_invalid_field) do
              args.merge(params: args[:params].merge('field_name' => 'nonexistent'))
            end

            it 'raises NotFoundError' do
              expect { update_field.handle_request(args_with_invalid_field) }
                .to raise_error(Http::Exceptions::NotFoundError, /does not exist/)
            end
          end

          context 'with non-array field' do
            let(:args_with_non_array_field) do
              args.merge(params: args[:params].merge('field_name' => 'title'))
            end

            it 'raises ValidationError' do
              expect { update_field.handle_request(args_with_non_array_field) }
                .to raise_error(Http::Exceptions::ValidationError, /not an array/)
            end
          end

          context 'with non-existent record' do
            before do
              allow(@collection).to receive(:list).and_return([])
            end

            it 'raises NotFoundError' do
              expect { update_field.handle_request(args) }
                .to raise_error(Http::Exceptions::NotFoundError, /not found/)
            end
          end

          context 'with index out of bounds' do
            let(:args_with_large_index) do
              args.merge(params: args[:params].merge('index' => '10'))
            end

            before do
              book = { 'id' => 1, 'tags' => ['one', 'two'] }
              allow(@collection).to receive(:list).and_return([book])
            end

            it 'raises ValidationError' do
              expect { update_field.handle_request(args_with_large_index) }
                .to raise_error(Http::Exceptions::ValidationError, /out of bounds/)
            end
          end

          context 'with negative index' do
            let(:args_with_negative_index) do
              args.merge(params: args[:params].merge('index' => '-1'))
            end

            it 'raises ValidationError' do
              expect { update_field.handle_request(args_with_negative_index) }
                .to raise_error(Http::Exceptions::ValidationError, /non-negative/)
            end
          end

          context 'with invalid index format' do
            let(:args_with_invalid_index) do
              args.merge(params: args[:params].merge('index' => 'abc'))
            end

            it 'raises ValidationError' do
              expect { update_field.handle_request(args_with_invalid_index) }
                .to raise_error(Http::Exceptions::ValidationError, /Invalid index/)
            end
          end

          context 'with field value not an array' do
            before do
              book = { 'id' => 1, 'tags' => nil }
              allow(@collection).to receive(:list).and_return([book])
            end

            it 'raises UnprocessableError' do
              expect { update_field.handle_request(args) }
                .to raise_error(Http::Exceptions::UnprocessableError, /not an array/)
            end
          end

          context 'with type coercion' do
            context 'string to number' do
              let(:args_with_string_number) do
                args.merge(
                  params: args[:params].merge(
                    'field_name' => 'scores',
                    data: { attributes: { 'value' => '99' } }
                  )
                )
              end

              it 'coerces string to number' do
                book = { 'id' => 1, 'scores' => [10, 20] }
                updated_book = { 'id' => 1, 'scores' => [99.0, 20] }

                allow(@collection).to receive(:list).and_return([book], [updated_book])
                allow(@collection).to receive(:update).and_return(true)

                result = update_field.handle_request(args_with_string_number)

                expect(@collection).to have_received(:update).with(
                  anything,
                  anything,
                  { scores: [99.0, 20] }
                )
              end
            end

            context 'invalid number coercion' do
              let(:args_with_invalid_number) do
                args.merge(
                  params: args[:params].merge(
                    'field_name' => 'scores',
                    data: { attributes: { 'value' => 'not-a-number' } }
                  )
                )
              end

              before do
                book = { 'id' => 1, 'scores' => [10, 20] }
                allow(@collection).to receive(:list).and_return([book])
              end

              it 'raises ValidationError' do
                expect { update_field.handle_request(args_with_invalid_number) }
                  .to raise_error(Http::Exceptions::ValidationError, /Cannot coerce/)
              end
            end
          end

          context 'with composite primary key' do
            before do
              @datasource_composite = Datasource.new
              @collection_composite = build_collection(
                name: 'composite_book',
                schema: {
                  fields: {
                    'tenant_id' => ColumnSchema.new(
                      column_type: 'Number',
                      is_primary_key: true,
                      filter_operators: [Operators::IN, Operators::EQUAL]
                    ),
                    'id' => ColumnSchema.new(
                      column_type: 'Number',
                      is_primary_key: true,
                      filter_operators: [Operators::IN, Operators::EQUAL]
                    ),
                    'tags' => ColumnSchema.new(column_type: '[String]')
                  }
                }
              )

              @datasource_composite.add_collection(@collection_composite)
              ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(@datasource_composite)
              ForestAdminAgent::Builder::AgentFactory.instance.build
            end

            let(:args_with_composite_key) do
              args.merge(
                params: args[:params].merge(
                  'collection_name' => 'composite_book',
                  'id' => '1|123'
                )
              )
            end

            it 'handles composite key correctly' do
              book = { 'tenant_id' => 1, 'id' => 123, 'tags' => ['old', 'tag'] }
              updated_book = { 'tenant_id' => 1, 'id' => 123, 'tags' => ['updated-tag', 'tag'] }

              allow(@collection_composite).to receive(:list).and_return([book], [updated_book])
              allow(@collection_composite).to receive(:update).and_return(true)

              result = update_field.handle_request(args_with_composite_key)

              expect(@collection_composite).to have_received(:update).with(
                anything,
                anything,
                { tags: ['updated-tag', 'tag'] }
              )
              expect(result[:content]['data']['attributes']['tags']).to eq(['updated-tag', 'tag'])
            end
          end
        end
      end
    end
  end
end
