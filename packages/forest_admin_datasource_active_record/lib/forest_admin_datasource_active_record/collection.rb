module ForestAdminDatasourceActiveRecord
  class Collection < ForestAdminDatasourceToolkit::Collection
    include Parser::Column
    include Parser::Relation

    def initialize(datasource, model)
      @model = model
      name = model.name.split('::').last
      super(datasource, name)
      fetch_fields
      fetch_associations
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
          is_sortable: true,
          default_value: column.default,
          enum_values: get_enum_values(column),
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
              foreign_collection: association.class_name,
              origin_key: association.foreign_key,
              origin_key_target: association.join_foreign_key
            )
          )
        when :belongs_to
          add_field(
            association.name.to_s,
            ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema.new(
              foreign_collection: association.class_name,
              foreign_key: association.foreign_key,
              foreign_key_target: association.join_foreign_key
            )
          )
        when :has_many
          if association.through_reflection?
            add_field(
              association.name.to_s,
              ForestAdminDatasourceToolkit::Schema::Relations::ManyToManySchema.new(
                foreign_collection: association.class_name,
                origin_key: association.through_reflection.join_foreign_key,
                origin_key_target: association.through_reflection.foreign_key,
                foreign_key: association.join_foreign_key,
                foreign_key_target: association.association_primary_key,
                through_collection: association.through_reflection.class_name
              )
            )
          else
            add_field(
              association.name.to_s,
              ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema.new(
                foreign_collection: association.class_name,
                origin_key: association.foreign_key, # TODO: remove hardcoded id
                origin_key_target: association.join_foreign_key
              )
            )
          end
        end
      end
    end
  end
end
