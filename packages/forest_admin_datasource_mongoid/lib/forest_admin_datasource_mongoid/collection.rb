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

      fetch_fields(@model)
      fetch_associations
      # enable_count
    end

    def list(_caller, filter, projection)
      Utils::Query.new(self, projection, filter)
                  .get
                  .map { |record| Utils::MongoidSerializer.new(record).to_hash(projection) }
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

    def fetch_fields(model, prefix = nil)
      model.fields.each do |column_name, column|
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

        if prefix
          add_field("#{prefix}.#{column_name}", field)
        else
          add_field(column_name, field)
        end
      end
    end

    def fetch_associations
      @model.relations.transform_values do |association|
        case association
        when Mongoid::Association::Referenced::HasMany
          add_field(
            association.name.to_s,
            ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema.new(
              foreign_collection: format_model_name(association.klass.name),
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
                foreign_collection: format_model_name(association.klass.name),
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
          # simplify this type of relationship by considering them to be sub-fields and encapsulating it in an array
          add_embedded_fields(association, "#{association.name}.[]")
        when Mongoid::Association::Embedded::EmbedsOne
          # simplify this type of relationship by considering them to be sub-fields
          add_embedded_fields(association, association.name)
        when Mongoid::Association::Referenced::HasAndBelongsToMany
          # datasource.simulate_habtm(model)
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
        else
          'unknown'
        end
      end
    end

    # def add_embedded_fields(association, prefix = '', depth = 0)
    #   fetch_fields(association.klass, prefix)
    #   association.klass.relations.each do |sub_name, sub_association|
    #     field_name = "#{prefix}.#{sub_name}"
    #
    #     if depth >= MAX_DEPTH
    #       make_field(field_name, Hash)
    #     else
    #       case sub_association
    #       when Mongoid::Association::Embedded::EmbedsOne
    #         make_field(field_name, Hash)
    #         add_embedded_fields(sub_association, field_name, depth + 1)
    #         debugger
    #       when Mongoid::Association::Embedded::EmbedsMany
    #         make_field(field_name, Array)
    #         add_embedded_fields(sub_association, "#{field_name}[]", depth + 1)
    #       else
    #         make_field(field_name, sub_association.class)
    #       end
    #     end
    #   end
    # end
    def add_embedded_fields(association, prefix = '')
      fetch_fields(association.klass, prefix)

      association.klass.relations.each do |sub_name, sub_association|
        field_name = "#{prefix}.#{sub_name}"

        next if sub_association.is_a?(Mongoid::Association::Embedded::EmbeddedIn)

        if sub_association.is_a?(Mongoid::Association::Embedded::EmbedsOne) ||
           sub_association.is_a?(Mongoid::Association::Embedded::EmbedsMany)
          make_field(field_name, Hash)
        else
          make_field(field_name, sub_association.class)
        end
      end
    end

    def make_field(name, type)
      schema[:fields][name] = ForestAdminDatasourceToolkit::Schema::ColumnSchema.new(
        column_type: type.to_s,
        is_primary_key: false,
        is_sortable: true
      )
    end
  end
end
