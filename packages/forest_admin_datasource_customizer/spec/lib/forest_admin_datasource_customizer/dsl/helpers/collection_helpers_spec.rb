# frozen_string_literal: true

require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module DSL
    describe CollectionHelpers do
      include ForestAdminDatasourceToolkit
      include ForestAdminDatasourceToolkit::Schema
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

      let(:datasource) { ForestAdminDatasourceToolkit::Datasource.new }
      let(:stack) { ForestAdminDatasourceCustomizer::Decorators::DecoratorsStack.new(datasource) }
      let(:datasource_customizer) { ForestAdminDatasourceCustomizer::DatasourceCustomizer.new }
      let(:collection_customizer) { ForestAdminDatasourceCustomizer::CollectionCustomizer.new(datasource_customizer, stack, 'books') }

      before do
        collection_book = instance_double(
          ForestAdminDatasourceToolkit::Collection,
          name: 'books',
          datasource: datasource,
          schema: {
            charts: [],
            fields: {
              'id' => ForestAdminDatasourceToolkit::Schema::ColumnSchema.new(column_type: 'Number', is_primary_key: true),
              'title' => ForestAdminDatasourceToolkit::Schema::ColumnSchema.new(column_type: 'String'),
              'author_id' => ForestAdminDatasourceToolkit::Schema::ColumnSchema.new(column_type: 'Number')
            }
          }
        )
        datasource.add_collection(collection_book)
        allow(datasource_customizer).to receive(:stack).and_return(stack)
      end

      describe '#computed_field' do
        it 'creates a computed field with the DSL syntax' do
          allow(collection_customizer).to receive(:add_field).with(
            'full_title',
            an_instance_of(Decorators::Computed::ComputedDefinition)
          )

          collection_customizer.computed_field :full_title, type: 'String', depends_on: [:title] do |records|
            records.map { |r| "Book: #{r["title"]}" }
          end

          expect(collection_customizer).to have_received(:add_field).with(
            'full_title',
            an_instance_of(Decorators::Computed::ComputedDefinition)
          )
        end

        it 'handles multiple dependencies' do
          definition = nil
          allow(collection_customizer).to receive(:add_field) do |_name, def_arg|
            definition = def_arg
          end

          collection_customizer.computed_field :computed,
                                               type: 'String',
                                               depends_on: %i[title author_id] do |records|
            records
          end

          expect(definition.dependencies).to eq(%w[title author_id])
        end

        it 'handles default value' do
          definition = nil
          allow(collection_customizer).to receive(:add_field) do |_name, def_arg|
            definition = def_arg
          end

          collection_customizer.computed_field :with_default,
                                               type: 'String',
                                               depends_on: [:title],
                                               default: 'N/A' do |records|
            records
          end

          expect(definition.default_value).to eq('N/A')
        end

        it 'raises error without block' do
          expect do
            collection_customizer.computed_field :invalid, type: 'String'
          end.to raise_error(ArgumentError, 'Block is required for computed field')
        end
      end

      describe '#action' do
        it 'creates an action with the DSL syntax' do
          allow(collection_customizer).to receive(:add_action).with(
            'approve',
            an_instance_of(Decorators::Action::BaseAction)
          )

          collection_customizer.action :approve, scope: :single do
            execute do
              success 'Approved!'
            end
          end

          expect(collection_customizer).to have_received(:add_action).with(
            'approve',
            an_instance_of(Decorators::Action::BaseAction)
          )
        end

        it 'creates an action with form' do
          action = nil
          allow(collection_customizer).to receive(:add_action) do |_name, action_arg|
            action = action_arg
          end

          collection_customizer.action :export, scope: :global do
            description 'Export all data'
            generates_file!

            form do
              field :format, type: :string
              field :include_deleted, type: :boolean
            end

            execute do
              file content: 'data', name: 'export.csv'
            end
          end

          expect(action.scope).to eq(Decorators::Action::Types::ActionScope::GLOBAL)
          expect(action.description).to eq('Export all data')
          expect(action.is_generate_file).to be true
          expect(action.form).to be_an(Array)
          expect(action.form.length).to eq(2)
        end

        it 'handles different scopes' do
          %i[single bulk global].each do |scope_sym|
            action = nil
            allow(collection_customizer).to receive(:add_action) do |_name, action_arg|
              action = action_arg
            end

            collection_customizer.action :test, scope: scope_sym do
              execute { success 'OK' }
            end

            expected_scope = case scope_sym
                             when :single then Decorators::Action::Types::ActionScope::SINGLE
                             when :bulk then Decorators::Action::Types::ActionScope::BULK
                             when :global then Decorators::Action::Types::ActionScope::GLOBAL
                             end

            expect(action.scope).to eq(expected_scope)
          end
        end

        it 'raises error without block' do
          expect do
            collection_customizer.action :invalid, scope: :single
          end.to raise_error(ArgumentError, 'Block is required for action')
        end
      end

      describe '#segment' do
        it 'creates a segment with the DSL syntax' do
          allow(collection_customizer).to receive(:add_segment).with('Active')

          collection_customizer.segment 'Active' do
            { field: 'is_active', operator: 'Equal', value: true }
          end

          expect(collection_customizer).to have_received(:add_segment).with('Active')
        end
      end

      describe '#before and #after hooks' do
        it 'creates before hooks' do
          allow(collection_customizer).to receive(:add_hook).with('before', 'create')

          collection_customizer.before(:create) { |_context| nil }

          expect(collection_customizer).to have_received(:add_hook).with('before', 'create')
        end

        it 'creates after hooks' do
          allow(collection_customizer).to receive(:add_hook).with('after', 'update')

          collection_customizer.after(:update) { |_context| nil }

          expect(collection_customizer).to have_received(:add_hook).with('after', 'update')
        end
      end

      describe '#belongs_to' do
        it 'creates a many-to-one relation' do
          allow(collection_customizer).to receive(:add_many_to_one_relation).with(
            'author',
            'authors',
            { foreign_key: 'author_id' }
          )

          collection_customizer.belongs_to :author, foreign_key: :author_id

          expect(collection_customizer).to have_received(:add_many_to_one_relation).with(
            'author',
            'authors',
            { foreign_key: 'author_id' }
          )
        end

        it 'allows custom collection name' do
          allow(collection_customizer).to receive(:add_many_to_one_relation).with(
            'writer',
            'people',
            { foreign_key: 'writer_id' }
          )

          collection_customizer.belongs_to :writer, collection: :people, foreign_key: :writer_id

          expect(collection_customizer).to have_received(:add_many_to_one_relation).with(
            'writer',
            'people',
            { foreign_key: 'writer_id' }
          )
        end
      end

      describe '#has_many' do
        it 'creates a one-to-many relation' do
          allow(collection_customizer).to receive(:add_one_to_many_relation).with(
            'books',
            'books',
            { origin_key: 'author_id' }
          )

          collection_customizer.has_many :books, origin_key: :author_id

          expect(collection_customizer).to have_received(:add_one_to_many_relation).with(
            'books',
            'books',
            { origin_key: 'author_id' }
          )
        end

        it 'creates a many-to-many relation with through' do
          allow(collection_customizer).to receive(:add_many_to_many_relation).with(
            'authors',
            'authors',
            'book_authors',
            { origin_key: 'book_id', foreign_key: 'author_id' }
          )

          collection_customizer.has_many :authors,
                                         through: :book_authors,
                                         origin_key: :book_id,
                                         foreign_key: :author_id

          expect(collection_customizer).to have_received(:add_many_to_many_relation).with(
            'authors',
            'authors',
            'book_authors',
            { origin_key: 'book_id', foreign_key: 'author_id' }
          )
        end
      end

      describe '#has_one' do
        it 'creates a one-to-one relation' do
          allow(collection_customizer).to receive(:add_one_to_one_relation).with(
            'profile',
            'profiles',
            { origin_key: 'user_id' }
          )

          collection_customizer.has_one :profile, origin_key: :user_id

          expect(collection_customizer).to have_received(:add_one_to_one_relation).with(
            'profile',
            'profiles',
            { origin_key: 'user_id' }
          )
        end
      end

      describe '#validates' do
        it 'adds field validation' do
          allow(collection_customizer).to receive(:add_field_validation).with(
            'email',
            'Email',
            nil
          )

          collection_customizer.validates :email, :email

          expect(collection_customizer).to have_received(:add_field_validation).with(
            'email',
            'Email',
            nil
          )
        end

        it 'adds validation with value' do
          allow(collection_customizer).to receive(:add_field_validation).with(
            'age',
            'GreaterThan',
            18
          )

          collection_customizer.validates :age, :greater_than, 18

          expect(collection_customizer).to have_received(:add_field_validation).with(
            'age',
            'GreaterThan',
            18
          )
        end
      end

      describe '#hide_fields' do
        it 'removes multiple fields' do
          allow(collection_customizer).to receive(:remove_field).with('internal', 'secret')

          collection_customizer.hide_fields :internal, :secret

          expect(collection_customizer).to have_received(:remove_field).with('internal', 'secret')
        end
      end

      describe '#disable_search' do
        it 'calls replace_search with a block' do
          # Just verify the method exists and doesn't error
          expect { collection_customizer.disable_search }.not_to raise_error
        end
      end

      describe '#enable_search' do
        it 'calls replace_search with custom block' do
          # Just verify the method exists and doesn't error
          expect do
            collection_customizer.enable_search do |query, _context|
              query
            end
          end.not_to raise_error
        end
      end

      describe '#chart' do
        it 'creates a chart with the DSL syntax' do
          allow(collection_customizer).to receive(:add_chart).with('total_records')

          collection_customizer.chart :total_records do
            value 1234
          end

          expect(collection_customizer).to have_received(:add_chart).with('total_records')
        end

        it 'creates a chart with distribution' do
          chart_block = nil
          allow(collection_customizer).to receive(:add_chart) do |_name, &block|
            chart_block = block
          end

          collection_customizer.chart :status_distribution do
            distribution(
              'Active' => 150,
              'Inactive' => 50
            )
          end

          expect(chart_block).not_to be_nil
        end

        it 'creates a chart with value' do
          chart_block = nil
          allow(collection_customizer).to receive(:add_chart) do |_name, &block|
            chart_block = block
          end

          collection_customizer.chart :monthly_total do
            value 50_000, 45_000
          end

          expect(chart_block).not_to be_nil
        end

        it 'creates a chart with context access' do
          chart_block = nil
          allow(collection_customizer).to receive(:add_chart) do |_name, &block|
            chart_block = block
          end

          collection_customizer.chart :dynamic_stats do
            # Access context to calculate dynamic values
            value 100
          end

          expect(chart_block).not_to be_nil
        end
      end
    end
  end
end
