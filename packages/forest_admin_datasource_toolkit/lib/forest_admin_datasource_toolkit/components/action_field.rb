module ForestAdminDatasourceToolkit
  module Components
    class ActionField
      attr_accessor :value
      attr_reader :type, :label, :description, :is_required, :is_read_only, :enum_values, :collection_name

      attr_writer :watch_changes

      def initialize(
        type:,
        label:,
        description: nil,
        is_required: false,
        is_read_only: false,
        value: nil,
        enum_values: nil,
        collection_name: nil,
        watch_changes: false
      )
        @type = type
        @label = label
        @description = description
        @is_required = is_required
        @is_read_only = is_read_only
        @value = value
        @enum_values = enum_values
        @collection_name = collection_name
        @watch_changes = watch_changes
      end
    end
  end
end
