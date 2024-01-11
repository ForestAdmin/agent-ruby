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

            split_path = path.split(':')
            relation = split_path[0]
            memo[relation] = Projection.new([split_path[1]].union(memo[relation] || []))
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

        def replace(&block)
          Projection.new(
            map(&block)
            .reduce(Projection.new) do |memo, path|
              return memo.union([path]) if path.is_a?(String)

              memo.union(path)
            end
          )
        end

        def equals(other)
          length == other.length && all? { |field| other.include?(field) }
        end
      end
    end
  end
end
