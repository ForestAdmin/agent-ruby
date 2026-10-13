module ForestAdminDatasourceToolkit
  module Components
    module Query
      # Frozen snapshot of a Projection's columns / relations, built once and walked for every record.
      # Projection itself is a mutable Array and cannot memoize them.
      ProjectionTree = Struct.new(:columns, :relations) do
        def self.build(projection)
          new(projection.columns.freeze, projection.relations.transform_values { |sub| build(sub) }.freeze).freeze
        end

        def re_project(record)
          project(record && ForestAdminDatasourceToolkit::Utils::HashHelper.convert_keys(record, :to_s))
        end

        protected

        def project(record)
          return unless record

          result = {}
          columns.each { |column| result[column.to_s] = record[column.to_s] }
          relations.each { |relation, sub_tree| result[relation] = sub_tree.project(record[relation]) }
          result
        end
      end
    end
  end
end
