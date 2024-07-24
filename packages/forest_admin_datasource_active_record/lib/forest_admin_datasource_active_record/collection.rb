module ForestAdminDatasourceActiveRecord
  class Collection < ForestAdminDatasourceToolkit::Collection
    include Parser::Column
    include Parser::Relation
    include ForestAdminDatasourceToolkit::Components::Query

    attr_reader :model

    def initialize(datasource, model)
      @model = model
      name = model.name.demodulize.underscore
      super(datasource, name)
      fetch_fields
      fetch_associations
      enable_count
    end

    def native_driver
      ActiveRecord::Base.connection
    end

    def list(_caller, filter, projection)
      query = Utils::Query.new(self, projection, filter)

      query.get.map { |record| Utils::ActiveRecordSerializer.new(record).to_hash(projection) }
    end

    def aggregate(_caller, filter, aggregation, limit = nil)
      Utils::QueryAggregate.new(self, aggregation, filter, limit).get
    end

    def create(_caller, data)
      Utils::ActiveRecordSerializer.new(@model.create(data)).to_hash
    end

    def update(_caller, filter, data)
      entity = Utils::Query.new(self, nil, filter).build.first
      entity.update(data)
    end

    def delete(_caller, filter)
      entities = Utils::Query.new(self, nil, filter).build
      entities&.each(&:destroy)
    end

    private

    def fetch_fields
      @model.columns_hash.each do |column_name, column|
        field = ForestAdminDatasourceToolkit::Schema::ColumnSchema.new(
          column_type: get_column_type(@model, column),
          filter_operators: operators_for_column_type(get_column_type(@model, column)),
          is_primary_key: column_name == @model.primary_key || @model.primary_key.include?(column_name),
          is_read_only: false,
          is_sortable: true,
          default_value: column.default,
          enum_values: get_enum_values(@model, column),
          # validations: get_validations(column)
          validations: []
        )

        add_field(column_name, field)
      end
    end

    def association_primary_key?(association)
      !association.association_primary_key.empty?
    rescue StandardError
      false
    end

    def fetch_associations
      associations(@model).each do |association|
        case association.macro
        when :has_one
          if association_primary_key?(association)
            add_field(
              association.name.to_s,
              ForestAdminDatasourceToolkit::Schema::Relations::OneToOneSchema.new(
                foreign_collection: format_model_name(association.class_name),
                origin_key: association.foreign_key,
                origin_key_target: association.association_primary_key
              )
            )
          end
        when :belongs_to
          if association_primary_key?(association)
            add_field(
              association.name.to_s,
              ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema.new(
                foreign_collection: format_model_name(association.class_name),
                foreign_key: association.foreign_key,
                foreign_key_target: association.association_primary_key
              )
            )
          end
        when :has_many
          if association_primary_key?(association)
            if association.through_reflection?
              add_field(
                association.name.to_s,
                ForestAdminDatasourceToolkit::Schema::Relations::ManyToManySchema.new(
                  foreign_collection: format_model_name(association.class_name),
                  origin_key: association.through_reflection.foreign_key,
                  origin_key_target: association.through_reflection.join_foreign_key,
                  foreign_key: association.join_foreign_key,
                  foreign_key_target: association.association_primary_key,
                  through_collection: format_model_name(association.through_reflection.class_name)
                )
              )
            else
              add_field(
                association.name.to_s,
                ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema.new(
                  foreign_collection: format_model_name(association.class_name),
                  origin_key: association.foreign_key,
                  origin_key_target: association.association_primary_key
                )
              )
            end
          end
        end
      end
    end
  end
end
