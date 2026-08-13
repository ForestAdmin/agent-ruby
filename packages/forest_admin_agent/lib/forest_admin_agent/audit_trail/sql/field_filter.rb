module ForestAdminAgent
  module AuditTrail
    module Sql
      # SQL keeping only the audit entries whose diff touched one of the given fields. Both JSON columns are
      # searched: a field the change added exists in `new_values` only, one it removed in `previous_values`
      # only.
      #
      # The test is per adapter, and a field name is always a whole key — never a path — so a name holding a
      # dot (`address.city`) has to be quoted or the database reads it as a traversal.
      class FieldFilter
        COLUMNS = %w[previous_values new_values].freeze

        def initialize(connection)
          @connection = connection
        end

        def condition(fields)
          adapter = @connection.adapter_name.downcase

          case adapter
          when /postgres/ then COLUMNS.map { |column| postgres_has_key(column, fields) }.join(' OR ')
          when /sqlite/ then json_paths(fields) { |column, path| "json_type(#{column}, #{path}) IS NOT NULL" }
          when /mysql|maria/ then mysql_has_keys(fields)
          else
            raise ForestAdminDatasourceToolkit::Exceptions::ForestException,
                  "Filtering the audit trail by field is not supported on #{adapter}"
          end
        end

        private

        # `jsonb_object_keys` rather than the `?|` operator: `?` is a bind placeholder for ActiveRecord and
        # the function form needs no escaping. The column is `json`, hence the cast.
        def postgres_has_key(column, fields)
          list = fields.map { |field| @connection.quote(field) }.join(', ')

          "EXISTS (SELECT 1 FROM jsonb_object_keys(#{column}::jsonb) AS key WHERE key IN (#{list}))"
        end

        # `json_type` and not `json_extract`: a key holding a JSON null extracts as SQL NULL, which would
        # read as "no such key".
        def json_paths(fields)
          COLUMNS.flat_map { |column| fields.map { |field| yield(column, json_path(field)) } }.join(' OR ')
        end

        def mysql_has_keys(fields)
          paths = fields.map { |field| json_path(field) }.join(', ')

          COLUMNS.map { |column| "JSON_CONTAINS_PATH(#{column}, 'one', #{paths})" }.join(' OR ')
        end

        def json_path(field)
          @connection.quote(%($."#{field.to_s.gsub(/["\\]/) { |char| "\\#{char}" }}"))
        end
      end
    end
  end
end
