module ForestAdminDatasourceActiveRecord
  class Collection < ForestAdminDatasourceToolkit::Collection
    include Column
    def initialize(datasource, model)
      @model = model
      name = model.name.split('::').last
      super(datasource, name)
      fetch_fields
    end

    private

    def fetch_fields
      @model.columns_hash.each do |column_name, column|
        # TODO: check is not sti column
        field = ForestAdminDatasourceToolkit::Schema::ColumnSchema.new(
          column_type: get_column_type(column),
          # filter_operators: [],
          is_primary_key: column_name == @model.primary_key,
          is_read_only: false,
          is_sortable: true
          # default_value: column.default,
          # enum_values: get_enum_values(column),
          # validations: get_validations(column)
        )

        add_field(column_name, field)
      end
    end
  end
end
