module ForestAdminDatasourceActiveRecord
  class Collection < ForestAdminDatasourceToolkit::Collection
    include Parser::Column
    include Parser::Relation
    include Parser::Validation
    include ForestAdminDatasourceToolkit::Components::Query

    attr_reader :model

    def initialize(datasource, model, support_polymorphic_relations: false)
      @model = model
      @support_polymorphic_relations = support_polymorphic_relations
      name = format_model_name(@model.name)
      super(datasource, name)
      fetch_fields
      fetch_associations
      enable_count
    end

    def native_driver
      ActiveRecord::Base.connection
    end

    def list(caller, filter, projection)
      # Check if the RenameCollectionDecorator marked that we should disable includes
      # to prevent ActiveRecord from preloading polymorphic associations with wrong type resolution
      disable_includes = false
      decorated_datasource = nil
      if caller
        request = caller.instance_variable_get(:@request)
        disable_includes = request&.dig(:disable_polymorphic_includes) || false
        decorated_datasource = request&.dig(:decorated_datasource)
      end

      # When disable_includes is true, we need to exclude polymorphic relations from both
      # query building and serialization to avoid polymorphic_class_for errors
      query_projection = projection
      query_projection = filter_polymorphic_relations_from_projection(projection) if disable_includes && projection

      # Pass decorated datasource (with renames) for resolving collection names in projections
      query = Utils::Query.new(self, query_projection, filter, disable_includes: disable_includes,
                                                               datasource: decorated_datasource)

      query.get.map { |record| Utils::ActiveRecordSerializer.new(record).to_hash(query_projection) }
    end

    def aggregate(_caller, filter, aggregation, limit = nil)
      Utils::QueryAggregate.new(self, aggregation, filter, limit).get
    end

    def create(caller, data)
      Utils::ErrorHandler.handle_errors(:create) do
        # Get datasource with decorators (including rename) for ProjectionFactory
        datasource = nil
        if caller&.instance_variable_defined?(:@request)
          request = caller.instance_variable_get(:@request)
          datasource = request[:decorated_datasource] if request.is_a?(Hash)
        end

        datasource ||= begin
          ForestAdminAgent::Facades::Container.datasource
        rescue StandardError
          nil
        end

        Utils::ActiveRecordSerializer.new(@model.create!(data)).to_hash(ProjectionFactory.all(self, datasource))
      end
    end

    def update(_caller, filter, data)
      Utils::ErrorHandler.handle_errors(:update) do
        entity = Utils::Query.new(self, nil, filter).build.first
        entity&.update!(data)
      end
    end

    def delete(_caller, filter)
      Utils::ErrorHandler.handle_errors(:delete) do
        entities = Utils::Query.new(self, nil, filter).build
        entities&.each(&:destroy)
      end
    end

    private

    def format_model_name(class_name)
      class_name.gsub('::', '__')
    end

    def fetch_fields
      @model.columns_hash.sort_by { |column_name, _| column_name }.each do |column_name, column|
        field = ForestAdminDatasourceToolkit::Schema::ColumnSchema.new(
          column_type: get_column_type(@model, column),
          filter_operators: operators_for_column_type(get_column_type(@model, column)),
          is_primary_key: column_name == @model.primary_key || @model.primary_key.include?(column_name),
          is_read_only: false,
          is_sortable: true,
          default_value: column.default,
          enum_values: get_enum_values(@model, column),
          validation: get_validations(column)
        )

        add_field(column_name, field)
      end
    end

    def association_primary_key?(association)
      !association.association_primary_key.empty?
    rescue StandardError
      association.polymorphic?
    end

    # rubocop:disable Metrics/BlockNesting
    def fetch_associations
      associations(@model, support_polymorphic_relations: @support_polymorphic_relations).each do |association|
        case association.macro
        when :has_one
          if association_primary_key?(association)
            if association.through_reflection?
              through_reflection = association.through_reflection
              is_polymorphic = through_reflection.options[:as].present?

              add_field(
                association.name.to_s,
                ForestAdminDatasourceToolkit::Schema::Relations::ManyToManySchema.new(
                  foreign_collection: format_model_name(association.klass.name),
                  origin_key: through_reflection.foreign_key,
                  origin_key_target: through_reflection.join_foreign_key,
                  foreign_key: association.join_foreign_key,
                  foreign_key_target: association.association_primary_key,
                  through_collection: format_model_name(through_reflection.klass.name),
                  origin_type_field: is_polymorphic ? through_reflection.type : nil,
                  origin_type_value: is_polymorphic ? @model.name : nil
                )
              )
            elsif association.inverse_of&.polymorphic? || association.options[:as].present?
              # Detect polymorphic has_one by checking either:
              # 1. inverse_of is polymorphic (standard case)
              # 2. association uses :as option (polymorphic target side)
              polymorphic_name = association.options[:as] || association.inverse_of&.name
              foreign_type_field = "#{polymorphic_name}_type"

              add_field(
                association.name.to_s,
                ForestAdminDatasourceToolkit::Schema::Relations::PolymorphicOneToOneSchema.new(
                  foreign_collection: format_model_name(association.klass.name),
                  origin_key: association.foreign_key,
                  origin_key_target: association.association_primary_key,
                  origin_type_field: foreign_type_field,
                  origin_type_value: @model.name
                )
              )
            else
              add_field(
                association.name.to_s,
                ForestAdminDatasourceToolkit::Schema::Relations::OneToOneSchema.new(
                  foreign_collection: format_model_name(association.klass.name),
                  origin_key: association.foreign_key,
                  origin_key_target: association_primary_key(association)
                )
              )
            end
          end
        when :belongs_to
          if association_primary_key?(association)
            if polymorphic?(association)
              foreign_collections = get_polymorphic_types(association)
              add_field(
                association.name.to_s,
                ForestAdminDatasourceToolkit::Schema::Relations::PolymorphicManyToOneSchema.new(
                  foreign_collections: foreign_collections.keys,
                  foreign_key: association.foreign_key,
                  foreign_key_type_field: association.foreign_type,
                  foreign_key_targets: foreign_collections
                )
              )

              warn_missing_polymorphic_columns(association)

              schema[:fields][association.foreign_key]&.is_read_only = true
              schema[:fields][association.foreign_type]&.is_read_only = true
            else
              add_field(
                association.name.to_s,
                ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema.new(
                  foreign_collection: format_model_name(association.klass.name),
                  foreign_key: association.foreign_key,
                  foreign_key_target: association.association_primary_key
                )
              )
            end
          end
        when :has_many
          if association_primary_key?(association)
            if association.through_reflection?
              through_reflection = association.through_reflection
              is_polymorphic = through_reflection.options[:as].present?

              add_field(
                association.name.to_s,
                ForestAdminDatasourceToolkit::Schema::Relations::ManyToManySchema.new(
                  foreign_collection: format_model_name(association.klass.name),
                  origin_key: through_reflection.foreign_key,
                  origin_key_target: through_reflection.join_foreign_key,
                  foreign_key: association.join_foreign_key,
                  foreign_key_target: association.association_primary_key,
                  through_collection: format_model_name(through_reflection.klass.name),
                  origin_type_field: is_polymorphic ? through_reflection.type : nil,
                  origin_type_value: is_polymorphic ? @model.name : nil
                )
              )
            elsif association.inverse_of&.polymorphic? || association.options[:as].present?
              # Detect polymorphic has_many by checking either:
              # 1. inverse_of is polymorphic (standard case)
              # 2. association uses :as option (polymorphic target side)
              polymorphic_name = association.options[:as] || association.inverse_of&.name
              foreign_type_field = "#{polymorphic_name}_type"

              add_field(
                association.name.to_s,
                ForestAdminDatasourceToolkit::Schema::Relations::PolymorphicOneToManySchema.new(
                  foreign_collection: format_model_name(association.klass.name),
                  origin_key: association.foreign_key,
                  origin_key_target: association.association_primary_key,
                  origin_type_field: foreign_type_field,
                  origin_type_value: @model.name
                )
              )
            else
              add_field(
                association.name.to_s,
                ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema.new(
                  foreign_collection: format_model_name(association.klass.name),
                  origin_key: association.foreign_key,
                  origin_key_target: association_primary_key(association)
                )
              )
            end
          end
        when :has_and_belongs_to_many
          through_collection_name = resolve_habtm_through_collection(association)
          add_field(
            association.name.to_s,
            ForestAdminDatasourceToolkit::Schema::Relations::ManyToManySchema.new(
              foreign_collection: format_model_name(association.klass.name),
              origin_key: association.join_primary_key,
              origin_key_target: association.join_foreign_key,
              foreign_key: association.association_foreign_key,
              foreign_key_target: association.association_primary_key,
              through_collection: through_collection_name
            )
          )
        end
      rescue StandardError => e
        logger = ActiveSupport::Logger.new($stdout)
        logger.warn(
          "[ForestAdmin] Unable to process association '#{association.name}' " \
          "in model '#{@model.name}': #{e.message}. Skipping this association."
        )
      end
    end
    # rubocop:enable Metrics/BlockNesting

    def resolve_habtm_through_collection(association)
      join_table = association.join_table.to_s
      through_model_name = association.join_table.classify

      # Check if the join table exists and has an 'id' column
      if ActiveRecord::Base.connection.table_exists?(join_table)
        columns = ActiveRecord::Base.connection.columns(join_table)
        has_id_column = columns.any? { |col| col.name == 'id' }

        if has_id_column
          begin
            through_model_name.constantize
          rescue NameError
            create_virtual_habtm_model(association, through_model_name)
          end
        end
      end

      format_model_name(through_model_name)
    end

    def create_virtual_habtm_model(association, model_name)
      parent_module = @model.name.deconstantize

      # Create the model class dynamically and assign to constant
      klass = if parent_module.empty?
                # Create in global namespace
                Object.const_set(model_name, Class.new(ActiveRecord::Base))
              else
                # Create in parent module namespace
                parent_module_obj = parent_module.constantize
                parent_module_obj.const_set(model_name.demodulize, Class.new(ActiveRecord::Base))
              end

      klass.table_name = association.join_table

      # Mark this as a virtual through collection so datasource doesn't try to add it again
      klass.const_set(:VIRTUAL_THROUGH_COLLECTION, true)

      # add associations
      klass.belongs_to association.active_record.name.demodulize.underscore.to_sym,
                       class_name: association.active_record.name,
                       foreign_key: association.join_foreign_key
      klass.belongs_to association.name.to_s.singularize.to_sym,
                       class_name: association.klass.name,
                       foreign_key: association.association_foreign_key

      logger = ActiveSupport::Logger.new($stdout)
      logger.info(
        "[ForestAdmin] Created virtual model '#{model_name}' for HABTM join table '#{association.join_table}' " \
        'with id column. This allows proper handling of the many-to-many relationship.'
      )

      klass
    end

    def warn_missing_polymorphic_columns(association)
      missing_columns = []
      missing_columns << association.foreign_key unless schema[:fields][association.foreign_key]
      missing_columns << association.foreign_type unless schema[:fields][association.foreign_type]

      return unless missing_columns.any?

      logger = ActiveSupport::Logger.new($stdout)
      columns_list = missing_columns.join(', ')
      logger.warn(
        "[ForestAdmin] ⚠️  Missing columns for polymorphic association '#{association.name}' " \
        "in model '#{@model.name}': #{columns_list}. " \
        'This may indicate pending migrations. Run `rails db:migrate:status` to check.'
      )
    end

    def filter_polymorphic_relations_from_projection(projection)
      return projection unless projection.is_a?(Array)

      # Projection is an Array of field paths like ['id', 'name', 'relation:id']
      # Filter out paths that start with polymorphic relation names
      polymorphic_relations = schema[:fields].select do |_name, field_schema|
        field_schema&.type&.start_with?('Polymorphic')
      end.keys

      # Create a new projection excluding polymorphic relation paths
      filtered = ForestAdminDatasourceToolkit::Components::Query::Projection.new
      projection.each do |field_path|
        # Check if this field path starts with a polymorphic relation
        relation_name = field_path.split(':').first
        next if polymorphic_relations.include?(relation_name)

        filtered << field_path
      end

      filtered
    end
  end
end
