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
    end

    def list(_caller, filter, projection)
      query = Utils::Query.new(self, projection, filter).build
      query.offset(filter.page.offset).limit(filter.page.limit).all
    end

    def aggregate(_caller, _filter, aggregation)
      field = aggregation.field || '*'

      [
        {
          value: @model.send(aggregation.operation.downcase, field),
          group: []
        }
      ]
    end

    def create(_caller, data)
      @model.create(data)
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
        # TODO: check is not sti column
        field = ForestAdminDatasourceToolkit::Schema::ColumnSchema.new(
          column_type: get_column_type(@model, column),
          # filter_operators: [],
          is_primary_key: column_name == @model.primary_key,
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

    def fetch_associations
      associations(@model).each do |association|
        case association.macro
        when :has_one
          add_field(
            association.name.to_s,
            ForestAdminDatasourceToolkit::Schema::Relations::OneToOneSchema.new(
              foreign_collection: association.class_name.demodulize.underscore,
              origin_key: association.foreign_key,
              origin_key_target: association.association_primary_key
            )
          )
        when :belongs_to
          add_field(
            association.name.to_s,
            ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema.new(
              foreign_collection: association.class_name.demodulize.underscore,
              foreign_key: association.foreign_key,
              foreign_key_target: association.association_primary_key
            )
          )
        when :has_many
          if association.through_reflection?
            add_field(
              association.name.to_s,
              ForestAdminDatasourceToolkit::Schema::Relations::ManyToManySchema.new(
                foreign_collection: association.class_name.demodulize.underscore,
                origin_key: association.through_reflection.join_foreign_key,
                origin_key_target: association.through_reflection.foreign_key,
                foreign_key: association.join_foreign_key,
                foreign_key_target: association.association_primary_key,
                through_collection: association.through_reflection.class_name.demodulize.underscore
              )
            )
          else
            add_field(
              association.name.to_s,
              ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema.new(
                foreign_collection: association.class_name.demodulize.underscore,
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
