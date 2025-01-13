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
      # fetch_associations
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
      # TODO
    end
  end
end
