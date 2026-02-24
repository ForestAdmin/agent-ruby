module ForestAdminDatasourceToolkit
  module Schema
    class ColumnSchema
      attr_reader :is_primary_key, :default_value, :enum_values, :type

      attr_accessor :is_read_only,
                    :is_sortable,
                    :is_groupable,
                    :validation,
                    :filter_operators,
                    :column_type

      def initialize(
        column_type:,
        filter_operators: [],
        is_primary_key: false,
        is_read_only: false,
        is_sortable: false,
        is_groupable: true,
        default_value: nil,
        enum_values: [],
        validation: []
      )
        @column_type = column_type
        @filter_operators = filter_operators
        @is_primary_key = is_primary_key
        @is_read_only = is_read_only
        @is_sortable = is_sortable
        @is_groupable = is_groupable
        @default_value = default_value
        @enum_values = enum_values
        @validation = validation
        @type = 'Column'
      end
    end
  end
end
