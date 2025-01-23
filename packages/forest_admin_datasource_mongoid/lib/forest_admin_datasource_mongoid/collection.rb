module ForestAdminDatasourceMongoid
  class Collection < ForestAdminDatasourceToolkit::Collection
    include Parser::Column
    include Parser::Validation
    include Parser::Relation
    include ForestAdminDatasourceToolkit::Components::Query

    MAX_DEPTH = 1

    attr_reader :model

    def initialize(datasource, model)
      @model = model
      name = format_model_name(@model.name)
      super(datasource, name)

      fetch_fields
      fetch_associations
      enable_count
    end

    def list(_caller, filter, projection)
      Utils::Query.new(self, projection, filter)
                  .get
                  .map { |record| Utils::MongoidSerializer.new(record).to_hash(projection) }
    end

    def aggregate(_caller, filter, aggregation, limit = nil)
      Utils::QueryAggregate.new(self, aggregation, filter, limit).get
    end

    def create(_caller, data)
      Utils::MongoidSerializer.new(@model.create(data)).to_hash(ProjectionFactory.all(self))
    end

    def update(_caller, filter, data)
      entity = Utils::Query.new(self, nil, filter).build.first
      entity&.update(data)
    end

    def delete(_caller, filter)
      entities = Utils::Query.new(self, nil, filter).build
      entities&.each(&:destroy)
    end

    private

    def format_model_name(class_name)
      class_name.gsub('::', '__')
    end

    def fetch_fields
      # Standard fields
      @model.fields.each do |column_name, column|
        field = ForestAdminDatasourceToolkit::Schema::ColumnSchema.new(
          column_type: get_column_type(column),
          filter_operators: operators_for_column_type(get_column_type(column)),
          is_primary_key: column.object_id_field? && column.association.nil?,
          is_read_only: false,
          is_sortable: true,
          default_value: column.object_id_field? ? nil : get_default_value(column),
          enum_values: [],
          validations: get_validations(column)
        )

        add_field(column_name, field)
      end

      # Embedded field (EmbedsMany and EmbedsOne)
      get_embedded_fields(@model).each do |column_name, column|
        field = ForestAdminDatasourceToolkit::Schema::ColumnSchema.new(
          column_type: get_column_type(column),
          is_primary_key: false,
          is_sortable: false
        )
        add_field(column_name, field)
      end
    end

    def fetch_associations
      @model.relations.transform_values do |association|
        case association
        when Mongoid::Association::Referenced::HasMany
          if association.polymorphic?
            add_field(
              association.name.to_s,
              ForestAdminDatasourceToolkit::Schema::Relations::PolymorphicOneToManySchema.new(
                foreign_collection: format_model_name(association.klass.name),
                origin_key: association.foreign_key,
                origin_key_target: association.primary_key,
                origin_type_field: association.type,
                origin_type_value: association.inverse_class_name.constantize
              )
            )
          else
            add_field(
              association.name.to_s,
              ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema.new(
                foreign_collection: format_model_name(association.klass.name),
                origin_key: association.foreign_key,
                origin_key_target: association.primary_key
              )
            )
          end
        when Mongoid::Association::Referenced::BelongsTo
          if association.polymorphic?
            foreign_collections = get_polymorphic_types(association.name)
            add_field(
              association.name.to_s,
              ForestAdminDatasourceToolkit::Schema::Relations::PolymorphicManyToOneSchema.new(
                foreign_collections: foreign_collections.keys,
                foreign_key: association.foreign_key,
                foreign_key_type_field: association.inverse_type,
                foreign_key_targets: foreign_collections
              )
            )
            schema[:fields][association.foreign_key].is_read_only = true
            schema[:fields][association.inverse_type].is_read_only = true
          else
            add_field(
              association.name.to_s,
              ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema.new(
                foreign_collection: format_model_name(association.klass.name),
                foreign_key: association.foreign_key,
                foreign_key_target: association.primary_key
              )
            )
          end
        when Mongoid::Association::Referenced::HasOne
          if association.polymorphic?
            add_field(
              association.name.to_s,
              ForestAdminDatasourceToolkit::Schema::Relations::PolymorphicOneToOneSchema.new(
                foreign_collection: format_model_name(association.klass.name),
                origin_key: association.foreign_key,
                origin_key_target: association.primary_key,
                origin_type_field: association.type,
                origin_type_value: association.inverse_class_name.constantize
              )
            )
          else
            add_field(
              association.name.to_s,
              ForestAdminDatasourceToolkit::Schema::Relations::OneToOneSchema.new(
                foreign_collection: format_model_name(association.klass.name),
                origin_key: association.foreign_key,
                origin_key_target: association.primary_key
              )
            )
          end
        when Mongoid::Association::Referenced::HasAndBelongsToMany
          foreign_key_of_association = association.klass.reflect_on_all_associations.find do |assoc|
            assoc.klass == association.inverse_class_name.constantize
          end&.foreign_key

          add_field(
            association.name.to_s,
            ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema.new(
              foreign_collection: format_model_name(association.klass.name),
              origin_key: foreign_key_of_association,
              origin_key_target: association.primary_key
            )
          )
        end
      end
    end
  end
end
