require 'spec_helper'
require 'singleton'

module ForestAdminAgent
  module Serializer
    include ForestAdminDatasourceToolkit
    include ForestAdminDatasourceToolkit::Schema
    include ForestAdminDatasourceToolkit::Schema::Relations
    include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

    describe ForestSerializer do
      describe 'nested includes' do
        before do
          datasource = Datasource.new

          country_collection = build_collection(
            name: 'Country',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true, filter_operators: [Operators::EQUAL]),
                'code' => ColumnSchema.new(column_type: 'String')
              }
            }
          )

          company_collection = build_collection(
            name: 'Company',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true, filter_operators: [Operators::EQUAL]),
                'name' => ColumnSchema.new(column_type: 'String'),
                'country_id' => ColumnSchema.new(column_type: 'Number'),
                'country' => ManyToOneSchema.new(
                  foreign_key: 'country_id',
                  foreign_key_target: 'id',
                  foreign_collection: 'Country'
                )
              }
            }
          )

          author_collection = build_collection(
            name: 'Author',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true, filter_operators: [Operators::EQUAL]),
                'name' => ColumnSchema.new(column_type: 'String'),
                'company_id' => ColumnSchema.new(column_type: 'Number'),
                'company' => ManyToOneSchema.new(
                  foreign_key: 'company_id',
                  foreign_key_target: 'id',
                  foreign_collection: 'Company'
                )
              }
            }
          )

          book_collection = build_collection(
            name: 'Book',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true, filter_operators: [Operators::EQUAL]),
                'title' => ColumnSchema.new(column_type: 'String'),
                'author_id' => ColumnSchema.new(column_type: 'Number'),
                'author' => ManyToOneSchema.new(
                  foreign_key: 'author_id',
                  foreign_key_target: 'id',
                  foreign_collection: 'Author'
                )
              }
            }
          )

          allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)
          [country_collection, company_collection, author_collection, book_collection].each do |collection|
            datasource.add_collection(collection)
          end
          ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(datasource)
          ForestAdminAgent::Builder::AgentFactory.instance.build
          @datasource = ForestAdminAgent::Facades::Container.datasource
        end

        let(:record) do
          {
            'id' => 1,
            'title' => 'Foundation',
            'author_id' => 10,
            'author' => {
              'id' => 10,
              'name' => 'Asimov',
              'company_id' => 100,
              'company' => {
                'id' => 100,
                'name' => 'Gnome Press',
                'country_id' => 1000,
                'country' => { 'id' => 1000, 'code' => 'US' }
              }
            }
          }
        end

        it 'serializes every level of a three-hop include' do
          result = JSONAPI::Serializer.serialize(
            record,
            class_name: 'Book',
            serializer: described_class,
            include: ['author', 'author.company', 'author.company.country']
          )

          included = result['included'].to_h { |resource| [resource['type'], resource] }

          expect(included.keys).to contain_exactly('Author', 'Company', 'Country')
          expect(included['Author']['id']).to eq('10')
          expect(included['Author']['attributes']['name']).to eq('Asimov')
          expect(included['Company']['id']).to eq('100')
          expect(included['Company']['attributes']['name']).to eq('Gnome Press')
          expect(included['Country']['id']).to eq('1000')
          expect(included['Country']['attributes']['code']).to eq('US')
        end

        it 'links each included resource to the next level so the client can walk the chain' do
          result = JSONAPI::Serializer.serialize(
            record,
            class_name: 'Book',
            serializer: described_class,
            include: ['author', 'author.company', 'author.company.country']
          )

          included = result['included'].to_h { |resource| [resource['type'], resource] }

          expect(result['data']['relationships']['author']['data']).to eq({ 'type' => 'Author', 'id' => '10' })
          expect(included['Author']['relationships']['company']['data']).to eq(
            { 'type' => 'Company', 'id' => '100' }
          )
          expect(included['Company']['relationships']['country']['data']).to eq(
            { 'type' => 'Country', 'id' => '1000' }
          )
        end

        it 'stops at the requested depth when a deeper level is not included' do
          result = JSONAPI::Serializer.serialize(
            record,
            class_name: 'Book',
            serializer: described_class,
            include: ['author', 'author.company']
          )

          expect(result['included'].map { |resource| resource['type'] }).to contain_exactly('Author', 'Company')
        end

        it 'skips a level whose related record is absent' do
          result = JSONAPI::Serializer.serialize(
            record.merge('author' => { 'id' => 10, 'name' => 'Asimov', 'company_id' => nil, 'company' => nil }),
            class_name: 'Book',
            serializer: described_class,
            include: ['author', 'author.company', 'author.company.country']
          )

          expect(result['included'].map { |resource| resource['type'] }).to eq(['Author'])
        end
      end

      describe 'a polymorphic relation nested under another relation' do
        before do
          datasource = Datasource.new

          car_collection = build_collection(
            name: 'Car',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true, filter_operators: [Operators::EQUAL]),
                'brand' => ColumnSchema.new(column_type: 'String')
              }
            }
          )

          author_collection = build_collection(
            name: 'Author',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true, filter_operators: [Operators::EQUAL]),
                'name' => ColumnSchema.new(column_type: 'String'),
                'documentable_id' => ColumnSchema.new(column_type: 'Number'),
                'documentable_type' => ColumnSchema.new(column_type: 'String'),
                'documentable' => PolymorphicManyToOneSchema.new(
                  foreign_key: 'documentable_id',
                  foreign_key_type_field: 'documentable_type',
                  foreign_collections: %w[Car],
                  foreign_key_targets: { 'Car' => 'id' }
                )
              }
            }
          )

          book_collection = build_collection(
            name: 'Book',
            schema: {
              fields: {
                'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true, filter_operators: [Operators::EQUAL]),
                'title' => ColumnSchema.new(column_type: 'String'),
                'author_id' => ColumnSchema.new(column_type: 'Number'),
                'author' => ManyToOneSchema.new(
                  foreign_key: 'author_id',
                  foreign_key_target: 'id',
                  foreign_collection: 'Author'
                )
              }
            }
          )

          allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)
          [car_collection, author_collection, book_collection].each { |c| datasource.add_collection(c) }
          ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(datasource)
          ForestAdminAgent::Builder::AgentFactory.instance.build
          @datasource = ForestAdminAgent::Facades::Container.datasource
        end

        it 'resolves the nested target from its type column' do
          record = {
            'id' => 1, 'title' => 'Foundation', 'author_id' => 10,
            'author' => {
              'id' => 10, 'name' => 'Asimov', 'documentable_id' => 7, 'documentable_type' => 'Car',
              'documentable' => { 'id' => 7, 'brand' => 'Toyota' }
            }
          }

          result = JSONAPI::Serializer.serialize(
            record, class_name: 'Book', serializer: described_class,
                    include: ['author', 'author.documentable']
          )

          included = result['included'].to_h { |resource| [resource['type'], resource] }
          expect(included.keys).to contain_exactly('Author', 'Car')
          expect(included['Car']['id']).to eq('7')
          expect(included['Car']['attributes']['brand']).to eq('Toyota')
          expect(included['Author']['relationships']['documentable']['data']).to eq(
            { 'type' => 'Car', 'id' => '7' }
          )
        end

        it 'rebuilds the linkage of a nested phantom target from the type and key columns' do
          record = {
            'id' => 1, 'title' => 'Foundation', 'author_id' => 10,
            'author' => {
              'id' => 10, 'name' => 'Asimov', 'documentable_id' => 7, 'documentable_type' => 'Car',
              'documentable' => { '*' => nil }
            }
          }

          result = JSONAPI::Serializer.serialize(
            record, class_name: 'Book', serializer: described_class,
                    include: ['author', 'author.documentable']
          )

          included = result['included'].to_h { |resource| [resource['type'], resource] }
          expect(included['Car']['id']).to eq('7')
          expect(included['Car']['links']['self']).to eq('/forest/Car/7')
          expect(included['Author']['relationships']['documentable']['data']).to eq(
            { 'type' => 'Car', 'id' => '7' }
          )
        end

        it 'omits the nested relation when the record it points at is unlinked' do
          record = {
            'id' => 1, 'title' => 'Foundation', 'author_id' => 10,
            'author' => {
              'id' => 10, 'name' => 'Asimov', 'documentable_id' => nil, 'documentable_type' => nil,
              'documentable' => { '*' => nil }
            }
          }

          result = JSONAPI::Serializer.serialize(
            record, class_name: 'Book', serializer: described_class,
                    include: ['author', 'author.documentable']
          )

          expect(result['included'].map { |resource| resource['type'] }).to eq(['Author'])
          expect(result['included'].first['relationships']['documentable']).not_to have_key('data')
        end

        it 'drops the nested relation instead of raising when its type column was not projected' do
          record = {
            'id' => 1, 'title' => 'Foundation', 'author_id' => 10,
            'author' => { 'id' => 10, 'name' => 'Asimov', 'documentable' => { 'id' => 7, 'brand' => 'Toyota' } }
          }

          result = JSONAPI::Serializer.serialize(
            record, class_name: 'Book', serializer: described_class,
                    include: ['author', 'author.documentable']
          )

          expect(result['included'].map { |resource| resource['type'] }).to eq(['Author'])
          expect(result['included'].first['relationships']['documentable']).not_to have_key('data')
        end
      end

      describe 'relationships' do
        describe 'PolymorphicManyToOne serialization' do
          before do
            datasource = Datasource.new

            car_collection = build_collection(
              name: 'Car',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true, filter_operators: [Operators::EQUAL]),
                  'brand' => ColumnSchema.new(column_type: 'String')
                }
              }
            )

            user_collection = build_collection(
              name: 'User',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true, filter_operators: [Operators::EQUAL]),
                  'name' => ColumnSchema.new(column_type: 'String')
                }
              }
            )

            # Namespaced model (Admin::User => Admin__User) with a custom primary key
            admin_user_collection = build_collection(
              name: 'Admin__User',
              schema: {
                fields: {
                  'reference' => ColumnSchema.new(column_type: 'String', is_primary_key: true, filter_operators: [Operators::EQUAL]),
                  'name' => ColumnSchema.new(column_type: 'String')
                }
              }
            )

            document_collection = build_collection(
              name: 'Document',
              schema: {
                fields: {
                  'id' => ColumnSchema.new(column_type: 'Number', is_primary_key: true, filter_operators: [Operators::EQUAL]),
                  'title' => ColumnSchema.new(column_type: 'String'),
                  'documentable_id' => ColumnSchema.new(column_type: 'Number'),
                  'documentable_type' => ColumnSchema.new(column_type: 'String'),
                  'documentable' => PolymorphicManyToOneSchema.new(
                    foreign_key: 'documentable_id',
                    foreign_key_type_field: 'documentable_type',
                    foreign_collections: %w[Car User Admin__User],
                    foreign_key_targets: { 'Car' => 'id', 'User' => 'id', 'Admin__User' => 'reference' }
                  )
                }
              }
            )

            allow(ForestAdminAgent::Builder::AgentFactory.instance).to receive(:send_schema).and_return(nil)
            datasource.add_collection(car_collection)
            datasource.add_collection(user_collection)
            datasource.add_collection(admin_user_collection)
            datasource.add_collection(document_collection)
            ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(datasource)
            ForestAdminAgent::Builder::AgentFactory.instance.build
            @datasource = ForestAdminAgent::Facades::Container.datasource
          end

          it 'serializes a polymorphic belongs_to relation pointing to Car' do
            record = {
              'id' => 1,
              'title' => 'Registration Certificate',
              'documentable_id' => 10,
              'documentable_type' => 'Car',
              'documentable' => { 'id' => 10, 'brand' => 'Toyota' }
            }

            result = JSONAPI::Serializer.serialize(record, class_name: 'Document', serializer: described_class)

            relationship = result['data']['relationships']['documentable']
            expect(relationship['data']['type']).to eq('Car')
            expect(relationship['data']['id']).to eq('10')
          end

          it 'builds the linkage id from the foreign key when the related record is a phantom (issue #332)' do
            # The AR datasource skips polymorphic relations while building the SELECT, so the related
            # object comes back without a primary key. The id must still be built from the owner FK.
            record = {
              'id' => 1,
              'title' => 'Registration Certificate',
              'documentable_id' => 10,
              'documentable_type' => 'Car',
              'documentable' => { '*' => nil }
            }

            result = JSONAPI::Serializer.serialize(record, class_name: 'Document', serializer: described_class)

            relationship = result['data']['relationships']['documentable']
            expect(relationship['data']['type']).to eq('Car')
            expect(relationship['data']['id']).to eq('10')
          end

          it 'builds the included document id and self-link from the foreign key (issue #332)' do
            record = {
              'id' => 1,
              'title' => 'Registration Certificate',
              'documentable_id' => 10,
              'documentable_type' => 'Car',
              'documentable' => { '*' => nil }
            }

            result = JSONAPI::Serializer.serialize(
              record, class_name: 'Document', serializer: described_class, include: 'documentable'
            )

            included = result['included'].find { |r| r['type'] == 'Car' }
            expect(included['id']).to eq('10')
            expect(included['links']['self']).to eq('/forest/Car/10')
          end

          it 'builds the linkage id for a namespaced target with a custom primary key (issue #332)' do
            # foreign_key_targets is keyed by the formatted name (Admin__User), but the type column
            # stores the raw class name (Admin::User); the lookup must reconcile the two.
            record = {
              'id' => 4,
              'title' => 'Audit Log',
              'documentable_id' => 'ref-42',
              'documentable_type' => 'Admin::User',
              'documentable' => { '*' => nil }
            }

            result = JSONAPI::Serializer.serialize(record, class_name: 'Document', serializer: described_class)

            relationship = result['data']['relationships']['documentable']
            expect(relationship['data']['type']).to eq('Admin__User')
            expect(relationship['data']['id']).to eq('ref-42')
          end

          it 'omits the data key for an unlinked polymorphic relation (issue #332)' do
            record = {
              'id' => 3,
              'title' => 'Orphan',
              'documentable_id' => nil,
              'documentable_type' => nil,
              'documentable' => { '*' => nil }
            }

            result = JSONAPI::Serializer.serialize(record, class_name: 'Document', serializer: described_class)

            expect(result['data']['relationships']['documentable']).not_to have_key('data')
          end

          it 'serializes a polymorphic belongs_to relation pointing to User' do
            record = {
              'id' => 2,
              'title' => 'ID Card',
              'documentable_id' => 5,
              'documentable_type' => 'User',
              'documentable' => { 'id' => 5, 'name' => 'John' }
            }

            result = JSONAPI::Serializer.serialize(record, class_name: 'Document', serializer: described_class)

            relationship = result['data']['relationships']['documentable']
            expect(relationship['data']['type']).to eq('User')
            expect(relationship['data']['id']).to eq('5')
          end
        end
      end
    end
  end
end
