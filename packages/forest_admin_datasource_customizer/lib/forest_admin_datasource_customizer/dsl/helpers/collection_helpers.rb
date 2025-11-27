# frozen_string_literal: true

require_relative '../builders/chart_builder'

module ForestAdminDatasourceCustomizer
  module DSL
    # CollectionHelpers provides Rails-like DSL methods for collection customization
    # These methods are included in CollectionCustomizer to provide a more idiomatic Ruby API
    # rubocop:disable Naming/PredicatePrefix
    module CollectionHelpers
      # Define a computed field with a cleaner syntax
      #
      # @example Simple computed field
      #   computed_field :full_name, type: 'String', depends_on: [:first_name, :last_name] do |records|
      #     records.map { |r| "#{r['first_name']} #{r['last_name']}" }
      #   end
      #
      # @example Computed relation
      #   computed_field :related_items, type: ['RelatedItem'], depends_on: [:id] do |records, context|
      #     records.map { |r| fetch_related(r['id']) }
      #   end
      #
      # @param name [String, Symbol] field name
      # @param type [String, Array<String>] field type (or array of types for relations)
      # @param depends_on [Array<String, Symbol>] fields this computation depends on
      # @param default [Object] default value
      # @param enum_values [Array] enum values if type is enum
      # @param block [Proc] computation block receiving (records, context)
      def computed_field(name, type:, depends_on: [], default: nil, enum_values: nil, &block)
        raise ArgumentError, 'Block is required for computed field' unless block

        add_field(
          name.to_s,
          Decorators::Computed::ComputedDefinition.new(
            column_type: type,
            dependencies: Array(depends_on).map(&:to_s),
            values: block,
            default_value: default,
            enum_values: enum_values
          )
        )
      end

      # Define a custom action with a fluent DSL
      #
      # @example Simple action
      #   action :approve, scope: :single do
      #     execute do
      #       success "Approved!"
      #     end
      #   end
      #
      # @example Action with form
      #   action :export, scope: :global do
      #     description "Export all customers"
      #     generates_file!
      #
      #     form do
      #       field :format, type: :string, widget: 'Dropdown',
      #             options: [{ label: 'CSV', value: 'csv' }]
      #     end
      #
      #     execute do
      #       format = form_value(:format)
      #       file content: generate_csv, name: "export.#{format}"
      #     end
      #   end
      #
      # @param name [String, Symbol] action name
      # @param scope [Symbol] action scope (:single, :bulk, :global)
      # @param block [Proc] action definition block
      def action(name, scope: :single, &block)
        raise ArgumentError, 'Block is required for action' unless block

        builder = ActionBuilder.new(scope: scope)
        builder.instance_eval(&block)
        add_action(name.to_s, builder.to_action)
      end

      # Define a segment with a cleaner syntax
      #
      # @example Static segment
      #   segment 'Active users' do
      #     { field: 'is_active', operator: 'Equal', value: true }
      #   end
      #
      # @example Dynamic segment
      #   segment 'High value customers' do
      #     { field: 'lifetime_value', operator: 'GreaterThan', value: 10000 }
      #   end
      #
      # @param name [String] segment name
      # @param block [Proc] block returning condition tree
      def segment(name, &block)
        add_segment(name, &block)
      end

      # Add a before hook for an operation
      #
      # @example
      #   before :create do |context|
      #     # Validate or transform data before create
      #   end
      #
      # @param operation [String, Symbol] operation name (:create, :update, :delete, :list, :aggregate)
      # @param block [Proc] hook handler
      def before(operation, &block)
        add_hook('before', operation.to_s, &block)
      end

      # Add an after hook for an operation
      #
      # @example
      #   after :create do |context|
      #     # Send notification after create
      #   end
      #
      # @param operation [String, Symbol] operation name (:create, :update, :delete, :list, :aggregate)
      # @param block [Proc] hook handler
      def after(operation, &block)
        add_hook('after', operation.to_s, &block)
      end

      # ActiveRecord-style belongs_to relation
      #
      # @example
      #   belongs_to :author, foreign_key: :author_id
      #
      # @param name [String, Symbol] relation name
      # @param collection [String, Symbol] target collection name (defaults to pluralized name)
      # @param foreign_key [String, Symbol] foreign key field
      def belongs_to(name, collection: nil, foreign_key: nil)
        collection_name = collection&.to_s || "#{name}s"
        foreign_key_name = foreign_key&.to_s || "#{name}_id"

        add_many_to_one_relation(
          name.to_s,
          collection_name,
          { foreign_key: foreign_key_name }
        )
      end

      # ActiveRecord-style has_many relation
      #
      # @example
      #   has_many :books, origin_key: :author_id
      #
      # @param name [String, Symbol] relation name
      # @param collection [String, Symbol] target collection name (defaults to name)
      # @param origin_key [String, Symbol] origin key field
      # @param foreign_key [String, Symbol] foreign key field (for many-to-many)
      # @param through [String, Symbol] through collection (for many-to-many)
      def has_many(name, collection: nil, origin_key: nil, foreign_key: nil, through: nil)
        collection_name = collection&.to_s || name.to_s

        if through
          # Many-to-many relation
          add_many_to_many_relation(
            name.to_s,
            collection_name,
            through.to_s,
            {
              origin_key: origin_key&.to_s,
              foreign_key: foreign_key&.to_s
            }.compact
          )
        else
          # One-to-many relation
          add_one_to_many_relation(
            name.to_s,
            collection_name,
            { origin_key: origin_key&.to_s }.compact
          )
        end
      end

      # ActiveRecord-style has_one relation
      #
      # @example
      #   has_one :profile, origin_key: :user_id
      #
      # @param name [String, Symbol] relation name
      # @param collection [String, Symbol] target collection name (defaults to pluralized name)
      # @param origin_key [String, Symbol] origin key field
      def has_one(name, collection: nil, origin_key: nil)
        collection_name = collection&.to_s || "#{name}s"

        add_one_to_one_relation(
          name.to_s,
          collection_name,
          { origin_key: origin_key&.to_s }.compact
        )
      end

      # Validate a field with a cleaner syntax
      #
      # @example Simple validation
      #   validates :email, :email
      #   validates :age, :greater_than, 18
      #
      # @param field_name [String, Symbol] field name
      # @param operator [String, Symbol] validation operator
      # @param value [Object] validation value (optional)
      def validates(field_name, operator, value = nil)
        # Convert snake_case to PascalCase
        operator_str = operator.to_s
                               .split('_')
                               .map(&:capitalize)
                               .join
        add_field_validation(field_name.to_s, operator_str, value)
      end

      # Hide fields from the schema
      #
      # @example
      #   hide_fields :internal_id, :secret_token
      #
      # @param field_names [Array<String, Symbol>] fields to hide
      def hide_fields(*field_names)
        remove_field(*field_names.map(&:to_s))
      end

      # Disable search on this collection
      def disable_search
        replace_search { |_query, _context| nil }
      end

      # Enable search with custom logic
      #
      # @example
      #   enable_search do |query, context|
      #     # Custom search logic
      #     query
      #   end
      #
      # @param block [Proc] search handler
      def enable_search(&block)
        replace_search(&block)
      end

      # Add a chart at the collection level with a cleaner syntax
      #
      # @example Simple value chart
      #   chart :num_records do
      #     value 1234
      #   end
      #
      # @example Distribution chart
      #   chart :status_distribution do
      #     distribution({
      #       'Active' => 150,
      #       'Inactive' => 50
      #     })
      #   end
      #
      # @example Chart with context
      #   chart :monthly_stats do |context|
      #     # Access the collection and calculate stats
      #     value calculated_value
      #   end
      #
      # @param name [String, Symbol] chart name
      # @param block [Proc] chart definition block
      def chart(name, &block)
        add_chart(name.to_s) do |context, result_builder|
          builder = DSL::ChartBuilder.new(context, result_builder)
          builder.instance_eval(&block)
        end
      end
    end
    # rubocop:enable Naming/PredicatePrefix
  end
end
