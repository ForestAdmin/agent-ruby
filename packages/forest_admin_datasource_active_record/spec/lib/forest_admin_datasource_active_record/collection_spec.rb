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

        it 'builds a full ManyToManySchema for a has_many :through sourced from a belongs_to' do
          field = collection.schema[:fields]['checks']

          expect(field).to have_attributes(
            class: Relations::ManyToManySchema,
            foreign_collection: 'Check',
            origin_key: 'car_id',
            origin_key_target: 'id',
            through_collection: 'CarCheck',
            foreign_key: 'check_id',
            foreign_key_target: 'id',
            origin_type_field: nil,
            origin_type_value: nil,
            foreign_type_field: nil,
            foreign_type_value: nil
          )
        end

        it 'do not add polymorphic relations' do
          expect(datasource.get_collection('User').schema[:fields].keys).not_to include('address')
          expect(datasource.get_collection('Address').schema[:fields].keys).not_to include('addressable')
        end

        it 'add has_and_belongs_to_many relation' do
          collection = described_class.new(datasource, Company)

          expect(collection.schema[:fields].keys).to include('users')
        end

        # Supplier -> Account -> AccountHistory is a has_one :through that isn't polymorphic,
        # so it never reaches the many_to_many_shape guard above -- it falls into this plain
        # OneToOneSchema branch instead, which hardcodes {AccountHistory,Supplier}'s own
        # primary keys unconditionally, regardless of the real FK or of whether the source is
        # a belongs_to (here it actually is one; account_history_id is a real column on
        # accounts, just never consulted by this branch). Unrelated to #370's guard, tracked
        # separately as #379; this test pins current (arguably wrong) behavior, not correct
        # behavior.
        it 'add has_one_through relation as a to-one (OneToOne)' do
          collection = described_class.new(datasource, Supplier)

          expect(collection.schema[:fields].keys).to include('account_history')

          field = collection.schema[:fields]['account_history']
          expect(field.class).to eq(Relations::OneToOneSchema)
          expect(field.foreign_collection).to eq('AccountHistory')
          expect(field.origin_key).to eq(AccountHistory.primary_key)
          expect(field.origin_key_target).to eq(Supplier.primary_key)
        end

        it 'skips association when foreign_key raises an error' do
          stub_const('ModelWithBrokenAssociation', Class.new(ApplicationRecord) do
            self.table_name = 'cars'
            self.abstract_class = true

            belongs_to :broken_relation, class_name: 'User'
          end)

          association = ModelWithBrokenAssociation.reflect_on_association(:broken_relation)
          allow(association).to receive(:foreign_key).and_raise(StandardError.new('undefined method for nil'))

          expect do
            described_class.new(datasource, ModelWithBrokenAssociation)
          end.not_to raise_error

          collection = described_class.new(datasource, ModelWithBrokenAssociation)
          expect(collection.schema[:fields].keys).not_to include('broken_relation')
        end

        it 'skips association when inverse_of raises an error' do
          stub_const('ModelWithBrokenInverse', Class.new(ApplicationRecord) do
            self.table_name = 'cars'
            self.abstract_class = true

            has_many :broken_has_many, class_name: 'User'
          end)

          association = ModelWithBrokenInverse.reflect_on_association(:broken_has_many)
          allow(association).to receive(:inverse_of).and_raise(StandardError.new('inverse_of failed'))

          expect do
            described_class.new(datasource, ModelWithBrokenInverse)
          end.not_to raise_error

          collection = described_class.new(datasource, ModelWithBrokenInverse)
          expect(collection.schema[:fields].keys).not_to include('broken_has_many')
        end

        context 'when has_and_belongs_to_many with id column in join table' do
          it 'creates virtual model and adds relation' do
            collection = described_class.new(datasource, Author)

            expect(collection.schema[:fields].keys).to include('books')
            expect(collection.schema[:fields]['books'].class).to eq(Relations::ManyToManySchema)
          end

          it 'creates virtual model with correct through_collection name' do
            collection = described_class.new(datasource, Author)

            books_relation = collection.schema[:fields]['books']
            expect(books_relation.through_collection).to eq('AuthorsBook')
          end

          it 'virtual model is constantizable' do
            described_class.new(datasource, Author)

            expect { 'AuthorsBook'.constantize }.not_to raise_error
            expect(AuthorsBook.table_name).to eq('authors_books')
          end

          it 'virtual model has belongs_to associations' do
            described_class.new(datasource, Author)

            author_association = AuthorsBook.reflect_on_association(:author)
            book_association = AuthorsBook.reflect_on_association(:book)

            expect(author_association).not_to be_nil
            expect(author_association.macro).to eq(:belongs_to)
            expect(author_association.class_name).to eq('Author')

            expect(book_association).not_to be_nil
            expect(book_association.macro).to eq(:belongs_to)
            expect(book_association.class_name).to eq('Book')
          end

          it 'does not recreate virtual model if already exists' do
            # First creation
            described_class.new(datasource, Author)
            first_class_object_id = AuthorsBook.object_id

            # Second creation should reuse existing model
            described_class.new(datasource, Book)
            second_class_object_id = AuthorsBook.object_id

            expect(first_class_object_id).to eq(second_class_object_id)
          end
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

        it 'sets cascade_on_delete=true on polymorphic has_many when dependent: :destroy is declared' do
          members = datasource.get_collection('Project').schema[:fields]['members']
          expect(members).to be_a(Relations::PolymorphicOneToManySchema)
          expect(members.cascade_on_delete).to be true
        end

        it 'leaves cascade_on_delete=false on polymorphic has_one without dependent option' do
          address = datasource.get_collection('User').schema[:fields]['address']
          expect(address).to be_a(Relations::PolymorphicOneToOneSchema)
          expect(address.cascade_on_delete).to be false
        end

        it 'sets foreign_type_field/value for has_many :through with polymorphic source_type' do
          user_collection = datasource.get_collection('User')
          projects_relation = user_collection.schema[:fields]['projects']

          expect(projects_relation).to be_a(Relations::ManyToManySchema)
          expect(projects_relation.foreign_type_field).to eq('memberable_type')
          expect(projects_relation.foreign_type_value).to eq('Project')
          expect(projects_relation.through_collection).to eq('Member')
          expect(projects_relation.foreign_key).to eq('memberable_id')
          expect(projects_relation.origin_key).to eq('user_id')
        end

        it 'does not set origin_type for has_many :through with source_type (non-polymorphic origin)' do
          user_collection = datasource.get_collection('User')
          projects_relation = user_collection.schema[:fields]['projects']

          expect(projects_relation.origin_type_field).to be_nil
          expect(projects_relation.origin_type_value).to be_nil
        end

        # In every `output(...).to_stdout` guard test below, `datasource` must be
        # dereferenced for the first time *inside* the `expect` block: Datasource#generate
        # builds every collection (and so triggers the warning) once, at construction. If
        # something earlier in the example touched `datasource` first, the matcher would
        # pass vacuously with no warning to catch -- the exact failure mode a previous
        # revision of this fix shipped with.
        it "skips a has_many :through whose foreign key is missing from the through collection, reproducing #370's exact symptom" do
          # Category -> Car (plain has_many) -> Check, through Car's OWN has_many :through
          # (Car#checks, through: :car_checks). NestedThroughProbe#checks's source_reflection
          # is Car#checks, which is itself a ThroughReflection, so join_foreign_key resolves
          # all the way down to CarCheck#check's real FK ("check_id") -- a genuine column
          # name, missing from Car specifically (not the generic "id" the bucket-B cases below
          # fall back to). This is the shape that actually produces #370's reported message.
          stub_const('NestedThroughProbe', Class.new(ApplicationRecord) do
            self.table_name = 'categories'
            self.abstract_class = true

            has_many :cars, foreign_key: :category_id
            has_many :checks, through: :cars, source: :checks
          end)

          association = NestedThroughProbe.reflect_on_association(:checks)
          expect(association.join_foreign_key).to eq('check_id')

          collection = nil
          expect do
            collection = described_class.new(datasource, NestedThroughProbe, support_polymorphic_relations: true)
          end.to output(/Skipping association 'checks'/).to_stdout

          expect(collection.schema[:fields].keys).not_to include('checks')
        end

        it 'still publishes, with a deprecation warning, a has_many :through whose foreign key ' \
           'coincidentally exists on the through collection' do
          # Parent -> Kid (polymorphic has_many) -> Detail (has_one, custom foreign_key). Kid#detail
          # is a has_one, so join_foreign_key resolves to Kid's own primary key ("id") -- a column
          # that trivially exists on every table, so it's not "missing" and the relation is still
          # published exactly as before, as an (until now undetected) identity join. Dropping it
          # outright would change the published schema for this shape, so it's deprecated instead.
          expect { datasource.get_collection('Parent') }.to output(/is published as a many-to-many/).to_stdout

          field = datasource.get_collection('Parent').schema[:fields]['details']
          expect(field).to have_attributes(
            class: Relations::ManyToManySchema,
            foreign_collection: 'Detail',
            origin_key: 'owner_id',
            origin_key_target: 'id',
            through_collection: 'Kid',
            foreign_key: 'id',
            foreign_key_target: 'id',
            origin_type_field: 'owner_type',
            origin_type_value: 'Parent',
            foreign_type_field: nil,
            foreign_type_value: nil
          )
        end

        it 'still publishes, with a deprecation warning, a polymorphic has_one :through with the same shape' do
          # Solo -> Kid (polymorphic has_one) -> Detail: same bucket-B shape as above, through the
          # has_one branch. A non-polymorphic has_one :through isn't reached by this guard at all --
          # it falls into the pre-existing OneToOneSchema path, unguarded (tracked as #379).
          expect { datasource.get_collection('Solo') }.to output(/is published as a many-to-many/).to_stdout

          field = datasource.get_collection('Solo').schema[:fields]['detail']
          expect(field).to have_attributes(
            class: Relations::ManyToManySchema,
            foreign_collection: 'Detail',
            origin_key: 'owner_id',
            origin_key_target: 'id',
            through_collection: 'Kid',
            foreign_key: 'id',
            foreign_key_target: 'id',
            origin_type_field: 'owner_type',
            origin_type_value: 'Solo',
            foreign_type_field: nil,
            foreign_type_value: nil
          )
        end

        it 'still publishes, with a deprecation warning, a non-polymorphic has_many :through with the same shape' do
          # Box -> Slot (plain has_many, no polymorphism at all) -> Tag: same bucket-B shape,
          # showing the has_many branch has no polymorphic gate -- it reaches this guard
          # unconditionally, unlike the has_one branch above.
          expect { datasource.get_collection('Box') }.to output(/is published as a many-to-many/).to_stdout

          field = datasource.get_collection('Box').schema[:fields]['tags']
          expect(field).to have_attributes(
            class: Relations::ManyToManySchema,
            foreign_collection: 'Tag',
            origin_key: 'box_id',
            origin_key_target: 'id',
            through_collection: 'Slot',
            foreign_key: 'id',
            foreign_key_target: 'id',
            origin_type_field: nil,
            origin_type_value: nil,
            foreign_type_field: nil,
            foreign_type_value: nil
          )
        end

        it 'does not warn when a many-to-many :through source is a belongs_to' do
          # datasource builds every collection eagerly on first dereference (see the guard
          # comment above), so a bare `not_to output(/is published as a many-to-many/)` would
          # also pick up Box/Parent/Solo's own deprecation warnings from that same eager build.
          # Naming the exact association+model excludes those unrelated warnings.
          expect { datasource.get_collection('User') }
            .not_to output(/Association 'projects' in model 'User' is published as a many-to-many/).to_stdout
        end

        it 'still publishes a has_many :through with a composite (array) foreign key on a belongs_to source' do
          # join_foreign_key can be an Array, not just a String, whenever the belongs_to source
          # declares a composite foreign_key (or query_constraints). column_names.include?(array)
          # is always false, so a naive "missing" check misclassifies this as unrepresentable and
          # drops a genuinely valid relation -- verified this fixture gets dropped without the
          # Array(...) handling in foreign_key_missing_from_through?.
          stub_const('CompositeLeaf', Class.new(ApplicationRecord) do
            self.table_name = 'cars'
            self.primary_key = %w[category_id reference]
            self.abstract_class = true
          end)

          stub_const('CompositeThrough', Class.new(ApplicationRecord) do
            self.table_name = 'car_checks'
            self.abstract_class = true

            belongs_to :leaf, class_name: 'CompositeLeaf', foreign_key: %w[car_id check_id],
                              primary_key: %w[category_id reference]
          end)

          stub_const('CompositeRoot', Class.new(ApplicationRecord) do
            self.table_name = 'categories'
            self.abstract_class = true

            has_many :throughs, class_name: 'CompositeThrough', foreign_key: :car_id
            has_many :leaves, through: :throughs, source: :leaf
          end)

          association = CompositeRoot.reflect_on_association(:leaves)
          expect(association.join_foreign_key).to eq(%w[car_id check_id])

          collection = described_class.new(datasource, CompositeRoot, support_polymorphic_relations: true)

          # This pins that foreign_key_target comes out mangled -- not that it's usable.
          # association_primary_key stringifies a composite target (ThroughReflection#
          # association_primary_key calls .to_s), so foreign_key_target is this mangled
          # string rather than a real column reference; that's a pre-existing (main-inherited)
          # limitation being pinned here, not endorsed.
          field = collection.schema[:fields]['leaves']
          expect(field).to have_attributes(
            class: Relations::ManyToManySchema,
            origin_key: 'car_id',
            origin_key_target: 'id',
            through_collection: 'CompositeThrough',
            foreign_key: %w[car_id check_id],
            foreign_key_target: '["category_id", "reference"]'
          )
        end

        it 'renders a composite (array) foreign key as a clean list in the deprecation warning' do
          # Same Array-valued join_foreign_key case as the belongs_to fixture above, but
          # sourced from a plain has_one (not belongs_to) so it reaches
          # warn_deprecated_identity_join instead -- pins that this message normalizes the
          # Array too, not just warn_unrepresentable_many_to_many.
          stub_const('ArrayLeaf', Class.new(ApplicationRecord) do
            self.table_name = 'users'
            self.abstract_class = true
          end)

          stub_const('ArrayThrough', Class.new(ApplicationRecord) do
            self.table_name = 'cars'
            self.primary_key = %w[category_id reference]
            self.abstract_class = true

            has_one :leaf, class_name: 'ArrayLeaf', foreign_key: :id
          end)

          stub_const('ArrayRoot', Class.new(ApplicationRecord) do
            self.table_name = 'categories'
            self.abstract_class = true

            has_many :throughs, class_name: 'ArrayThrough', foreign_key: :category_id
            has_many :leaves, through: :throughs, source: :leaf
          end)

          association = ArrayRoot.reflect_on_association(:leaves)
          expect(association.join_foreign_key).to eq(%w[category_id reference])

          expect do
            described_class.new(datasource, ArrayRoot, support_polymorphic_relations: true)
          end.to output(/joining 'ArrayThrough'\.'category_id, reference' to 'ArrayLeaf'\.'id'/).to_stdout
        end

        # rubocop:disable RSpec/ExampleLength
        it 'handles polymorphic associations with missing foreign key columns' do
          # This test reproduces issue #202: Server crashing on startup when missing columns for foreign keys
          # When a model declares a polymorphic belongs_to but the foreign key columns don't exist in the database
          # (e.g., pending migration), the agent should not crash

          # First, add the polymorphic columns to the Address model temporarily for this test
          ActiveRecord::Migration.suppress_messages do
            unless Address.column_names.include?('commentable_id')
              ActiveRecord::Migration.add_column :addresses, :commentable_id, :integer
            end
            unless Address.column_names.include?('commentable_type')
              ActiveRecord::Migration.add_column :addresses, :commentable_type, :string
            end
            Address.reset_column_information
          end

          stub_const('ModelWithMissingFkColumns', Class.new(ApplicationRecord) do
            self.table_name = 'addresses'
            self.abstract_class = true

            # Declaring a polymorphic association
            belongs_to :commentable, polymorphic: true
          end)

          # Temporarily remove the columns from the model's column cache to simulate missing columns
          # This simulates the scenario where the model has associations declared but the migration hasn't run yet
          excluded_columns = %w[commentable_id commentable_type]
          allow(ModelWithMissingFkColumns).to receive_messages(
            columns_hash: Address.columns_hash.except(*excluded_columns),
            columns: Address.columns.reject { |c| excluded_columns.include?(c.name) }
          )

          # Should not raise an error even though commentable_id and commentable_type are not in columns_hash
          expect do
            described_class.new(datasource, ModelWithMissingFkColumns)
          end.not_to raise_error

          collection = described_class.new(datasource, ModelWithMissingFkColumns)
          # The foreign key columns should not be in the schema since they're not in columns_hash
          expect(collection.schema[:fields].keys).not_to include('commentable_id', 'commentable_type')

          # Clean up
          ActiveRecord::Migration.suppress_messages do
            if Address.column_names.include?('commentable_id')
              ActiveRecord::Migration.remove_column :addresses, :commentable_id
            end
            if Address.column_names.include?('commentable_type')
              ActiveRecord::Migration.remove_column :addresses, :commentable_type
            end
            Address.reset_column_information
          end
        end
        # rubocop:enable RSpec/ExampleLength
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

    describe '#native_driver' do
      let(:datasource) { Datasource.new({ adapter: 'sqlite3', database: 'db/database.db' }) }
      let(:collection) { described_class.new(datasource, Car) }

      it 'yields a connection and releases it after the block' do
        collection.native_driver do |conn|
          expect(conn).to be_a(ActiveRecord::ConnectionAdapters::AbstractAdapter)
        end
      end
    end
  end
end
