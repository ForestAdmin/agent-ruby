require 'spec_helper'
require 'singleton'
require 'ostruct'
require 'shared/caller'

module ForestAdminAgent
  module Routes
    module Resources
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Schema
      describe Store do
        include_context 'with caller'
        subject(:store) { described_class.new }
        let(:args) do
          {
            headers: { 'HTTP_AUTHORIZATION' => bearer },
            params: {
              'collection_name' => 'book',
              'timezone' => 'Europe/Paris'
            }
          }
        end

        it 'adds the route forest_store' do
          store.setup_routes
          expect(store.routes.include?('forest_store')).to be true
          expect(store.routes.length).to eq 1
        end

        describe 'simple case' do
          before do
            book_class = Struct.new(:id, :title, :published_at, :price) do
              # def name
              #   'book'
              # end

              def respond_to?(arg)
                return false if arg == :each

                super arg
              end
            end
            stub_const('Book', book_class)
          end

          it 'call create and return an serialized content' do
            attributes = {
              'title' => 'Harry potter and the goblet of fire',
              'published_at' => '2000-07-07T21:00:00.000Z',
              'price' => 6.75
            }

            datasource = Datasource.new
            collection = Collection.new(datasource, 'book')
            collection.add_fields(
              {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'title' => ColumnSchema.new(column_type: 'String'),
                'published_at' => ColumnSchema.new(column_type: 'Date'),
                'price' => ColumnSchema.new(column_type: 'Number')
              }
            )
            allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)
            datasource.add_collection(collection)
            ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(datasource)
            ForestAdminAgent::Builder::AgentFactory.instance.build
            args[:params][:data] = { attributes: attributes, type: 'books' }
            book = Book.new(1, attributes['title'], attributes['published_at'], attributes['price'])

            allow(collection).to receive(:create).and_return(book)
            result = store.handle_request(args)
            expect(result[:name]).to eq('book')
            expect(result[:content]).to eq(
              'data' =>
                {
                  'type' => 'book',
                  'id' => '1',
                  'attributes' => {
                    'id' => 1,
                    'title' => 'Harry potter and the goblet of fire',
                    'published_at' => '2000-07-07T21:00:00.000Z',
                    'price' => 6.75
                  },
                  'links' => { 'self' => 'forest/book/1' }
                }
            )
          end
        end

        describe 'with relation' do
          before do
            person_class = Struct.new(:id, :name) do
              def respond_to?(arg)
                return false if arg == :each

                super arg
              end
            end

            passport_class = Struct.new(:id, :person_id) do
              def respond_to?(arg)
                return false if arg == :each

                super arg
              end
            end
            stub_const('Person', person_class)
            stub_const('Passport', passport_class)

            @datasource = Datasource.new
            collection_person = Collection.new(@datasource, 'person')
            collection_person.add_fields(
              {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'name' => ColumnSchema.new(column_type: 'String'),
                'passport' => Relations::OneToOneSchema.new(
                  origin_key: 'person_id',
                  origin_key_target: 'id',
                  foreign_collection: 'passport'
                )
              }
            )

            collection_passport = Collection.new(@datasource, 'passport')
            collection_passport.add_fields(
              {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true),
                'person_id' => ColumnSchema.new(column_type: 'Number'),
                'person' => Relations::ManyToOneSchema.new(
                  foreign_key: 'person_id',
                  foreign_key_target: 'id',
                  foreign_collection: 'passport'
                )
              }
            )
            @datasource.add_collection(collection_person)
            @datasource.add_collection(collection_passport)
            allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)
            ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(@datasource)
            ForestAdminAgent::Builder::AgentFactory.instance.build
          end

          describe 'with one to one relation' do
            it 'call create and return an serialized content' do
              args[:params][:data] = {
                attributes: { 'name' => 'john' },
                relationships: { 'passport' => { 'data' => { 'type' => 'passports', 'id' => 1 } } },
                type: 'persons'
              }
              args[:params]['collection_name'] = 'person'

              allow(@datasource.collection('person')).to receive(:create).and_return(Person.new(1, 'john'))
              allow(@datasource.collection('passport')).to receive(:update).and_return(Passport.new(1, 1))
              result = store.handle_request(args)
              expect(result[:name]).to eq('person')
              expect(result[:content]).to eq(
                'data' =>
                  {
                    'type' => 'person',
                    'id' => '1',
                    'attributes' => { 'id' => 1, 'name' => 'john' },
                    'links' => { 'self' => 'forest/person/1' },
                    'relationships' => {
                      'passport' => {
                        'data' => nil,
                        'links' => { 'related' => { 'href' => 'forest/person/1/relationships/passport' } }
                      }
                    }
                  }
              )
            end
          end

          describe 'with many to one relation' do
            it 'call create and return an serialized content' do
              args[:params][:data] = {
                attributes: {},
                relationships: { 'person' => { 'data' => { 'type' => 'person', 'id' => 1 } } },
                type: 'persons'
              }
              args[:params]['collection_name'] = 'passport'

              allow(@datasource.collection('passport')).to receive(:create).and_return(Passport.new(1, 1))
              result = store.handle_request(args)
              expect(result[:name]).to eq('passport')
              expect(result[:content]).to eq(
                'data' =>
                  {
                    'type' => 'passport',
                    'id' => '1',
                    'attributes' => { 'id' => 1, 'person_id' => 1 },
                    'links' => { 'self' => 'forest/passport/1' },
                    'relationships' => {
                      'person' => {
                        'data' => nil,
                        'links' => {
                          'related' => {
                            'href' => 'forest/passport/1/relationships/person'
                          }
                        }
                      }
                    }
                  }
              )
            end
          end
        end
      end
    end
  end
end
