module ForestAdminDatasourceToolkit
  module Components
    module Query
      class ProjectionFactory
        include ForestAdminDatasourceToolkit::Utils
        def self.all(collection)
          projection_fields = collection.fields.reduce([]) do |memo, path|
            column_name = path[0]
            schema = path[1]
            if schema.type == 'Column'
              memo = memo + [column_name]
            end

            if (schema.type == 'OneToOne' || schema.type == 'ManyToOne')
              relation = collection.datasource.collection(schema.foreign_collection)
              relation_columns = relation.fields
                                       .reject { |_relation_column_name, relation_column| relation_column.type != 'Column' }
                                       .keys
                                       .map { |relation_column_name| "#{column_name}:#{relation_column_name}" }

              memo = memo + relation_columns
            end

            memo
          end

          Projection.new projection_fields
        end
      end
    end
  end
end
