module ForestAdminDatasourceMongoid
  class ThroughCollection < ForestAdminDatasourceToolkit::Collection
    include Parser::Column
    # include Parser::Relation
    include ForestAdminDatasourceToolkit::Components::Query

    attr_reader :model, :options

    def initialize(datasource, options = {})
      # @model = model
      # name = format_model_name(@model.name)
      @options = options
      super(datasource, options[:name])
      add_relations
    end

    def add_relations
      @options[:associations].each do |association|
        # todo
        # field = ForestAdminDatasourceToolkit::Schema::ColumnSchema.new(
        #   column_type: get_column_type(column),
        #   filter_operators: operators_for_column_type(get_column_type(column)),
        #   is_primary_key: column.object_id_field?,
        #   is_read_only: false,
        #   is_sortable: true,
        #   default_value: column.object_id_field? ? nil : get_default_value(column),
        #   enum_values: get_enum_values(column),
        #   # validations: get_validations(column)
        #   validations: []
        # )
        #
        # add_field(column_name, field)

        add_field(
          association[:name].to_s,
          ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema.new(
            foreign_collection: association[:foreign_collection],
            foreign_key: association[:foreign_key],
            foreign_key_target: association[:foreign_key_target]
          )
        )
      end

      # add_field(
      #   association.name.to_s,
      #   ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema.new(
      #     foreign_collection: format_model_name(association.class_name),
      #     foreign_key: association.foreign_key,
      #     foreign_key_target: association.primary_key
      #   )
      # )
    end
  end
end
