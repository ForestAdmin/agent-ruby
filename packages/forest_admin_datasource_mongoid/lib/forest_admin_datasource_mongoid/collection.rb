module ForestAdminDatasourceMongoid
  class Collection < ForestAdminDatasourceToolkit::Collection
    include Parser::Column
    include Parser::Validation
    # include Parser::Relation
    include ForestAdminDatasourceToolkit::Components::Query

    attr_reader :model

    def initialize(datasource, model)
      @model = model
      name = format_model_name(@model.name)
      super(datasource, name)

      fetch_fields
      fetch_associations
      # enable_count
    end

    def list(_caller, _filter, projection)
      # query = Utils::Query.new(self, projection, filter)

      @model.all.map { |record| Utils::MongoidSerializer.new(record).to_hash(projection) }
    end

    def aggregate(_caller, filter, aggregation, limit = nil)
      # Utils::QueryAggregate.new(self, aggregation, filter, limit).get
    end

    def create(_caller, data)
      # Utils::ActiveRecordSerializer.new(@model.create(data)).to_hash(ProjectionFactory.all(self))
    end

    def update(_caller, filter, data)
      # entity = Utils::Query.new(self, nil, filter).build.first
      # entity&.update(data)
    end

    def delete(_caller, filter)
      # entities = Utils::Query.new(self, nil, filter).build
      # entities&.each(&:destroy)
    end

    private

    def format_model_name(class_name)
      class_name.gsub('::', '__')
    end

    def fetch_fields
      @model.fields.each do |column_name, column|
        field = ForestAdminDatasourceToolkit::Schema::ColumnSchema.new(
          column_type: get_column_type(column),
          filter_operators: operators_for_column_type(get_column_type(column)),
          is_primary_key: column.object_id_field?,
          is_read_only: false,
          is_sortable: true,
          default_value: column.object_id_field? ? nil : get_default_value(column),
          enum_values: [],
          validations: get_validations(column)
        )

        add_field(column_name, field)
      end
    end

    def fetch_associations
      @model.relations.transform_values do |association|
        case association
        when Mongoid::Association::Referenced::HasMany
          add_field(
            association.name.to_s,
            ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema.new(
              foreign_collection: format_model_name(association.class_name),
              origin_key: association.foreign_key,
              origin_key_target: association.primary_key
            )
          )
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
                foreign_collection: format_model_name(association.class_name),
                foreign_key: association.foreign_key,
                foreign_key_target: association.primary_key
              )
            )
          end
        when Mongoid::Association::Referenced::HasOne
          add_field(
            association.name.to_s,
            ForestAdminDatasourceToolkit::Schema::Relations::OneToOneSchema.new(
              foreign_collection: format_model_name(association.klass.name),
              origin_key: association.foreign_key,
              origin_key_target: association.primary_key
            )
          )
        when Mongoid::Association::Embedded::EmbedsMany
          # 'embeds_many'
        when Mongoid::Association::Embedded::EmbedsOne
          # 'embeds_one'
        when Mongoid::Association::Referenced::HasAndBelongsToMany
          datasource.simulate_habtm(model)

          add_field(
            association.name.to_s,
            ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema.new(
              foreign_collection: format_model_name(association.class_name),
              origin_key: association.foreign_key,
              origin_key_target: association.primary_key
            )
          )
        else
          'unknown'
        end
      end
    end
  end
end
