module ForestAdminDatasourceToolkit
  module Components
    module Query
      class Projection < Array
        include ForestAdminDatasourceToolkit::Utils
        def with_pks(collection)
          ForestAdminDatasourceToolkit::Utils::Schema.primary_keys(collection).each do |key|
            push(key) unless include?(key)
          end

          relations.each do |relation, projection|
            schema = collection.schema[:fields][relation]
            next unless schema.type != 'PolymorphicManyToOne'

            association = collection.datasource.get_collection(schema.foreign_collection)
            projection_with_pks = projection.with_pks(association).nest(prefix: relation)

            projection_with_pks.each { |field| push(field) unless include?(field) }
          end

          self
        end

        def columns
          reject { |field| field.include?(':') }
        end

        def relations
          each_with_object({}) do |path, memo|
            next unless path.include?(':')

            original_path = path.split(':')
            next if original_path.size == 1

            relation = original_path.shift

            memo[relation] = Projection.new([original_path.join(':')].union(memo[relation] || []))
          end
        end

        def nest(prefix: nil)
          prefix ? Projection.new(map { |path| "#{prefix}:#{path}" }) : self
        end

        def unnest
          prefix = first.split(':')[0]
          raise 'Cannot unnest projection.' unless all? { |path| path.start_with?(prefix) }

          Projection.new(map { |path| path[prefix.length + 1, path.length - prefix.length - 1] })
        end

        def replace(...)
          Projection.new(
            map(...)
              .reduce(Projection.new) do |memo, path|
              if path.is_a?(String)
                memo.union([path])
              else
                memo.union(path)
              end
            end
          )
        end

        def equals(other)
          length == other.length && all? { |field| other.include?(field) }
        end

        def apply(records)
          records.map { |record| re_project(record) }
        end

        def re_project(record)
          result = nil

          if record
            record = HashHelper.convert_keys(record, :to_s)
            result = {}
            columns.each { |column| result[column.to_s] = record[column.to_s] }
            relations.each { |relation, projection| result[relation] = projection.re_project(record[relation]) }
          end

          result
        end

        def union(other_arrays)
          Projection.new(other_arrays.to_a.union(self))
        end
      end
    end
  end
end
