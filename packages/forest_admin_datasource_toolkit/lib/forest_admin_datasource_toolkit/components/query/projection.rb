module ForestAdminDatasourceToolkit
  module Components
    module Query
      class Projection < Array
        include ForestAdminDatasourceToolkit::Utils
        def with_pks(collection)
          ForestAdminDatasourceToolkit::Utils::Schema.primary_keys(collection).each do | key |
            self.push(key) unless self.include?(key)
          end

          self.relations.each do | relation, projection |
            schema = collection.fields[relation]
            association = collection.datasource.collection(schema.foreign_collection)
            projection_with_pks = projection.with_pks(association).nest(prefix: relation)

            projection_with_pks.each { | field | self.push(field) unless self.include?(field) }
          end

          return self
        end

        def columns
          self.select { |field| !field.include?(':') }
        end

        def relations
          self.reduce({}) do |memo, path|
            if(path.include?(':'))
              split_path = path.split(':')
              relation = split_path[0]
              memo[relation] = Projection.new([split_path[1]].union(memo[relation] || []))
            end

            memo
          end
        end

        def nest(prefix: nil)
          prefix ? Projection.new(self.map { | path | "#{prefix}:#{path}"}) : self
        end
      end
    end
  end
end

