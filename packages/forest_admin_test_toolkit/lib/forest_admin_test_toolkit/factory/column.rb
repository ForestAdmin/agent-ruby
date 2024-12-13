module ForestAdminTestToolkit
  module Factory
    module Column
      include ForestAdminDatasourceToolkit::Schema
      include ForestAdminDatasourceToolkit::Validations

      def build_column(args = {})
        ColumnSchema.new(column_type: 'String', **args)
      end

      def build_numeric_primary_key(args = {})
        ColumnSchema.new(
          is_primary_key: true,
          column_type: 'Number',
          filter_operators: Rules.get_allowed_operators_for_column_type('Number'),
          **args
        )
      end

      def build_uuid_primary_key(args = {})
        ColumnSchema.new(
          is_primary_key: true,
          column_type: 'Uuid',
          filter_operators: Rules.get_allowed_operators_for_column_type('Uuid'),
          **args
        )
      end

      def build_many_to_many(args = {})
        Relations::ManyToManySchema.new(origin_key_target: 'id', foreign_key_target: 'id', **args)
      end

      def build_many_to_one(args = {})
        Relations::ManyToOneSchema.new(foreign_key_target: 'id', **args)
      end

      def build_one_to_one(args = {})
        Relations::OneToOneSchema.new(origin_key_target: 'id', **args)
      end

      def build_one_to_many(args = {})
        Relations::OneToManySchema.new(origin_key_target: 'id', **args)
      end
    end
  end
end
