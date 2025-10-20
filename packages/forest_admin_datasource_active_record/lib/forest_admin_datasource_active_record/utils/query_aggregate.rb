module ForestAdminDatasourceActiveRecord
  module Utils
    class QueryAggregate < Query
      include ForestAdminDatasourceToolkit::Components::Query::ConditionTree
      include ForestAdminDatasourceToolkit::Components::Query

      def initialize(collection, aggregation, filter = nil, limit = nil)
        filter ||= Filter.new
        super(collection, ForestAdminDatasourceToolkit::Components::Query::Projection.new, filter)
        @aggregation = aggregation
        @limit = limit
        @operation = aggregation.operation.downcase
        @field = aggregation.field.nil? ? '*' : format_field(aggregation.field)
      end

      def get
        build_select(@collection, @projection)
        apply_filter

        group_fields = []
        @aggregation.groups.each do |group|
          field = format_field(group[:field])
          if group[:operation]
            date_trunc_expression = date_trunc_sql(group[:operation], field)
            @select << "#{date_trunc_expression} AS \"#{group[:field]}\""
            group_fields << date_trunc_expression
          else
            @select << "#{field} AS \"#{group[:field]}\""
            group_fields << field
          end
        end

        @select << "#{@operation}(#{@field}) AS #{@operation}"
        @query = @query.order("#{@operation} DESC")
        @query = @query.limit(@limit) if @limit
        @query = @query.group(group_fields.join(','))
        apply_select

        compute_result_aggregate(@query)
      end

      def compute_result_aggregate(rows)
        rows.map do |row|
          {
            'value' => row.send(@operation.to_sym),
            'group' => @aggregation.groups.each_with_object({}) do |group, memo|
              memo[group[:field]] = row.send(group[:field].to_sym)
            end
          }
        end
      end

      def add_join_relation(relation_name)
        @query = @query.left_joins(relation_name.to_sym)

        @query
      end

      # Whitelist of valid date truncation operations
      VALID_DATE_OPERATIONS = %w[
        second
        minute
        hour
        day
        week
        month
        quarter
        year
      ].freeze

      # Valid relation types for field access
      VALID_RELATION_TYPES = %w[ManyToOne OneToOne].freeze

      private

      def date_trunc_sql(operation, field)
        adapter_name = @collection.model.connection.adapter_name.downcase
        operation = operation.to_s.downcase

        # Validate operation is in whitelist to prevent SQL injection
        unless VALID_DATE_OPERATIONS.include?(operation)
          raise ForestAdminDatasourceToolkit::Exceptions::ValidationError,
                "Invalid date truncation operation: '#{operation}'. " \
                "Allowed values: #{VALID_DATE_OPERATIONS.join(", ")}"
        end

        # Validate field exists in collection schema to prevent SQL injection
        validate_field_exists!(field)

        case adapter_name
        when 'postgresql'
          "DATE_TRUNC('#{operation}', #{field})"
        when 'mysql2', 'mysql'
          mysql_date_trunc(operation, field)
        when 'sqlite3', 'sqlite'
          sqlite_date_trunc(operation, field)
        else
          raise ArgumentError, "Unsupported database adapter '#{adapter_name}' for date truncation"
        end
      end

      def validate_field_exists!(field)
        if field.include?(':')
          validate_relation_field(field)
        elsif field.include?('.')
          validate_table_qualified_field(field)
        else
          validate_simple_field(field)
        end
      end

      def validate_relation_field(field)
        relation_name, field_name = field.split(':', 2)

        unless @collection.schema[:fields].key?(relation_name)
          raise ForestAdminDatasourceToolkit::Exceptions::ValidationError,
                "Invalid field: relation '#{relation_name}' does not exist in collection '#{@collection.name}'"
        end

        relation = @collection.schema[:fields][relation_name]
        unless VALID_RELATION_TYPES.include?(relation.type)
          raise ForestAdminDatasourceToolkit::Exceptions::ValidationError,
                "Invalid field: '#{relation_name}' is not a valid relation type for field access"
        end

        related_collection = @collection.datasource.get_collection(relation.foreign_collection)
        return if related_collection.schema[:fields].key?(field_name)

        raise ForestAdminDatasourceToolkit::Exceptions::ValidationError,
              "Invalid field: '#{field_name}' does not exist in related collection '#{relation.foreign_collection}'"
      end

      def validate_table_qualified_field(field)
        table_name, field_name = field.split('.', 2)

        if @collection.model.table_name == table_name
          return if @collection.schema[:fields].key?(field_name)

          raise ForestAdminDatasourceToolkit::Exceptions::ValidationError,
                "Invalid field: '#{field_name}' does not exist in collection '#{@collection.name}'"
        end

        # It's a joined table - validate it's from a valid relation
        relation_field = @collection.schema[:fields].find { |_name, f| VALID_RELATION_TYPES.include?(f.type) }
        return unless relation_field.nil?

        raise ForestAdminDatasourceToolkit::Exceptions::ValidationError,
              "Invalid field: table '#{table_name}' is not accessible from collection '#{@collection.name}'"
      end

      def validate_simple_field(field)
        return if @collection.schema[:fields].key?(field)

        raise ForestAdminDatasourceToolkit::Exceptions::ValidationError,
              "Invalid field: '#{field}' does not exist in collection '#{@collection.name}'"
      end

      # rubocop:disable Layout/LineLength
      def mysql_date_trunc(operation, field)
        case operation
        when 'year'
          "DATE_FORMAT(#{field}, '%Y-01-01 00:00:00')"
        when 'quarter'
          "DATE_FORMAT(#{field}, CONCAT(YEAR(#{field}), '-', LPAD((QUARTER(#{field}) - 1) * 3 + 1, 2, '0'), '-01 00:00:00'))"
        when 'month'
          "DATE_FORMAT(#{field}, '%Y-%m-01 00:00:00')"
        when 'week'
          "DATE_SUB(#{field}, INTERVAL WEEKDAY(#{field}) DAY)"
        when 'day'
          "DATE(#{field})"
        when 'hour'
          "DATE_FORMAT(#{field}, '%Y-%m-%d %H:00:00')"
        when 'minute'
          "DATE_FORMAT(#{field}, '%Y-%m-%d %H:%i:00')"
        when 'second'
          "DATE_FORMAT(#{field}, '%Y-%m-%d %H:%i:%s')"
        else
          raise ArgumentError, "Unsupported date truncation operation '#{operation}' for MySQL"
        end
      end
      # rubocop:enable Layout/LineLength

      # rubocop:disable Layout/LineLength
      def sqlite_date_trunc(operation, field)
        case operation
        when 'year'
          "strftime('%Y-01-01 00:00:00', #{field}, 'localtime')"
        when 'quarter'
          "strftime('%Y-', #{field}, 'localtime') || printf('%02d', ((CAST(strftime('%m', #{field}, 'localtime') AS INTEGER) - 1) / 3) * 3 + 1) || '-01 00:00:00'"
        when 'month'
          "strftime('%Y-%m-01 00:00:00', #{field}, 'localtime')"
        when 'week'
          "datetime(#{field}, 'localtime', 'weekday 0', '-6 days')"
        when 'day'
          "strftime('%Y-%m-%d 00:00:00', #{field}, 'localtime')"
        when 'hour'
          "strftime('%Y-%m-%d %H:00:00', #{field}, 'localtime')"
        when 'minute'
          "strftime('%Y-%m-%d %H:%M:00', #{field}, 'localtime')"
        when 'second'
          "strftime('%Y-%m-%d %H:%M:%S', #{field}, 'localtime')"
        else
          raise ArgumentError, "Unsupported date truncation operation '#{operation}' for SQLite"
        end
      end
      # rubocop:enable Layout/LineLength
    end
  end
end
