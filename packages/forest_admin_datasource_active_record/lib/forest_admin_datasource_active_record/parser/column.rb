module ForestAdminDatasourceActiveRecord
  module Parser
    module Column
      TYPES = {
        boolean: 'Boolean',
        datetime: 'Date',
        date: 'Dateonly',
        integer: 'Number',
        float: 'Number',
        decimal: 'Number',
        json: 'Json',
        jsonb: 'Json',
        hstore: 'Json',
        string: 'String',
        text: 'String',
        citext: 'String',
        time: 'Time',
        uuid: 'Uuid',
        binary: 'Binary'
      }.freeze

      def get_column_type(column)
        is_array = (column.respond_to?(:array) && column.array == true)
        is_array ? "[#{TYPES[column.type]}]" : TYPES[column.type]
      end

      def get_enum_values(column)
        enum_values = []
        if get_column_type(column) == 'Enum'
          if sti_column?(column)
            @model.descendants.each { |sti_model| enum_values << sti_model.name }
          else
            @model.defined_enums[column.name].each { |name, _value| enum_values << name }
          end
        end
        enum_values
      end

      def sti_column?(column)
        @model.inheritance_column && column.name == @model.inheritance_column
      end
    end
  end
end
