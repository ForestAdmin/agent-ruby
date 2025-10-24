require 'spec_helper'

module ForestAdminDatasourceActiveRecord
  include ForestAdminDatasourceToolkit::Schema
  describe Collection do
    context 'without polymorphic support' do
      let(:datasource) { Datasource.new({ adapter: 'sqlite3', database: 'db/database.db' }) }
      let(:collection) do
        described_class.new(datasource, Car)
      end

      describe 'fetch_fields' do
        it 'add all fields of model to the collection' do
          expect(collection.schema[:fields].keys).to include(
            'id',
            'category_id',
            'reference',
            'model',
            'brand',
            'year',
            'nb_seats',
            'is_manual',
            'options',
            'created_at',
            'updated_at'
          )
        end
      end

      describe 'fetch_associations' do
        it 'add all relation of model to the collection' do
          expect(collection.schema[:fields].keys).to include('category', 'user', 'car_checks', 'checks')
        end

        it 'do not add polymorphic relations' do
          expect(datasource.get_collection('User').schema[:fields].keys).not_to include('address')
          expect(datasource.get_collection('Address').schema[:fields].keys).not_to include('addressable')
        end

        it 'add has_and_belongs_to_many relation' do
          collection = described_class.new(datasource, Company)

          expect(collection.schema[:fields].keys).to include('users')
        end

        it 'add has_one_through relation' do
          collection = described_class.new(datasource, Supplier)

          expect(collection.schema[:fields].keys).to include('account_history')

          expect(collection.schema[:fields]['account_history'].class).to eq(Relations::ManyToManySchema)
        end
      end
    end

    context 'with polymorphic support' do
      let(:datasource) do
        Datasource.new({ adapter: 'sqlite3', database: 'db/database.db' }, support_polymorphic_relations: true)
      end
      let(:collection) do
        described_class.new(datasource, Car)
      end

      describe 'fetch_associations' do
        it 'add polymorphic relations' do
          expect(datasource.get_collection('User').schema[:fields].keys).to include('address')
          expect(datasource.get_collection('Address').schema[:fields].keys).to include('addressable')
        end
      end
    end

    context 'with custom primary keys' do
      describe 'association_primary_key' do
        it 'uses custom primary_key from association options for has_one' do
          stub_const('CustomPkModel1', Class.new(ApplicationRecord) do
            self.table_name = 'cars'
            self.primary_key = 'reference'
            self.abstract_class = true

            has_one :related_model, class_name: 'RelatedModel1', foreign_key: 'car_reference', primary_key: 'reference'
          end)

          stub_const('RelatedModel1', Class.new(ApplicationRecord) do
            self.table_name = 'users'
            self.abstract_class = true
          end)

          datasource = Datasource.new({ adapter: 'sqlite3', database: 'db/database.db' })
          collection = described_class.new(datasource, CustomPkModel1)
          relation_schema = collection.schema[:fields]['related_model']

          # The origin_key_target should be the custom primary_key specified in the association
          expect(relation_schema.origin_key_target).to eq('reference')
        end

        it 'uses custom primary_key from association options for belongs_to' do
          stub_const('CustomPkModel2', Class.new(ApplicationRecord) do
            self.table_name = 'cars'
            self.primary_key = 'reference'
            self.abstract_class = true
          end)

          stub_const('RelatedModel2', Class.new(ApplicationRecord) do
            self.table_name = 'users'
            self.abstract_class = true

            belongs_to :custom_pk_model, class_name: 'CustomPkModel2', foreign_key: 'car_id', primary_key: 'reference'
          end)

          datasource = Datasource.new({ adapter: 'sqlite3', database: 'db/database.db' })
          collection = described_class.new(datasource, RelatedModel2)
          relation_schema = collection.schema[:fields]['custom_pk_model']

          # The foreign_key_target should be the custom primary_key specified in the association
          expect(relation_schema.foreign_key_target).to eq('reference')
        end

        it 'falls back to default primary key when no custom primary_key is specified' do
          stub_const('DefaultPkModel', Class.new(ApplicationRecord) do
            self.table_name = 'cars'
            self.abstract_class = true

            has_one :user
          end)

          datasource = Datasource.new({ adapter: 'sqlite3', database: 'db/database.db' })
          collection = described_class.new(datasource, DefaultPkModel)
          relation_schema = collection.schema[:fields]['user']

          # Should use the default primary key from the User model
          expect(relation_schema.origin_key_target).to eq('id')
        end
      end

      describe 'composite primary keys support' do
        it 'handles composite primary keys in has_one associations' do
          stub_const('CompositePkModel1', Class.new(ApplicationRecord) do
            self.table_name = 'cars'
            self.primary_key = %w[reference category_id]
            self.abstract_class = true

            has_one :related_composite, class_name: 'RelatedComposite1', foreign_key: %w[car_reference car_category],
                                        primary_key: %w[reference category_id]
          end)

          stub_const('RelatedComposite1', Class.new(ApplicationRecord) do
            self.table_name = 'users'
            self.abstract_class = true
          end)

          datasource = Datasource.new({ adapter: 'sqlite3', database: 'db/database.db' })
          collection = described_class.new(datasource, CompositePkModel1)
          relation_schema = collection.schema[:fields]['related_composite']

          # With composite keys, origin_key_target is converted to a string representation
          # The association_primary_key method calls .to_s on arrays
          expect(relation_schema.origin_key_target).to eq('["reference", "category_id"]')
        end

        it 'handles composite primary keys in belongs_to associations' do
          stub_const('CompositePkModel2', Class.new(ApplicationRecord) do
            self.table_name = 'cars'
            self.primary_key = %w[reference category_id]
            self.abstract_class = true
          end)

          stub_const('RelatedComposite2', Class.new(ApplicationRecord) do
            self.table_name = 'users'
            self.abstract_class = true

            belongs_to :composite_pk_model, class_name: 'CompositePkModel2', foreign_key: %w[car_reference car_category],
                                            primary_key: %w[reference category_id]
          end)

          datasource = Datasource.new({ adapter: 'sqlite3', database: 'db/database.db' })
          collection = described_class.new(datasource, RelatedComposite2)
          relation_schema = collection.schema[:fields]['composite_pk_model']

          # With composite keys in belongs_to, foreign_key_target remains as an array
          # (different behavior than has_one which calls .to_s)
          expect(relation_schema.foreign_key_target).to eq(%w[reference category_id])
        end
      end

      describe 'association_primary_key method behavior' do
        it 'returns string when custom primary_key is a symbol' do
          stub_const('SymbolPkModel', Class.new(ApplicationRecord) do
            self.table_name = 'cars'
            self.abstract_class = true

            has_one :related, class_name: 'RelatedSymbol', foreign_key: 'car_id', primary_key: :reference
          end)

          stub_const('RelatedSymbol', Class.new(ApplicationRecord) do
            self.table_name = 'users'
            self.abstract_class = true
          end)

          datasource = Datasource.new({ adapter: 'sqlite3', database: 'db/database.db' })
          # Create collection directly since abstract_class models aren't auto-discovered
          collection = described_class.new(datasource, SymbolPkModel)
          relation_schema = collection.schema[:fields]['related']

          expect(relation_schema.origin_key_target).to be_a(String)
          expect(relation_schema.origin_key_target).to eq('reference')
        end

        it 'handles nil custom primary_key by falling back to association default' do
          # When primary_key option is explicitly nil, should use association's default
          stub_const('NilPkModel', Class.new(ApplicationRecord) do
            self.table_name = 'cars'
            self.abstract_class = true

            has_one :user, primary_key: nil
          end)

          datasource = Datasource.new({ adapter: 'sqlite3', database: 'db/database.db' })
          collection = described_class.new(datasource, NilPkModel)
          relation_schema = collection.schema[:fields]['user']

          # Should fall back to the default primary key
          expect(relation_schema.origin_key_target).to eq('id')
        end
      end
    end
  end
end
