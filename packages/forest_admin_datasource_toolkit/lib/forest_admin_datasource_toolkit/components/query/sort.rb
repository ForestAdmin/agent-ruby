module ForestAdminDatasourceToolkit
  module Components
    module Query
      class Sort < Array
        def projection
          Projection.new(map { |clause| clause[:field] })
        end

        def replace_clauses(...)
          Sort.new(
            map(...)
            .reduce(Sort.new) do |memo, clause|
              if clause.is_a?(Array) || clause.is_a?(self.class)
                memo.union(clause)
              else
                memo.union([clause])
              end
            end
          )
        end

        def nest(prefix)
          if prefix&.length
            self.class.new(map do |ob|
                             { field: "#{prefix}:#{ob[:field]}", ascending: ob[:ascending] }
                           end)
          else
            self
          end
        end

        def inverse
          self.class.new(map { |ob| { field: ob[:field], ascending: !ob[:ascending] } })
        end

        def unnest
          prefix = first[:field].split(':')[0]
          raise 'Cannot unnest sort.' unless all? { |ob| ob[:field].start_with?(prefix) }

          self.class.new(map do |ob|
                           { field: ob[:field][prefix.length + 1, ob[:field].length - prefix.length - 1],
                             ascending: ob[:ascending] }
                         end)
        end

        def apply(records)
          records.sort do |a, b|
            comparison = 0
            (0..(length - 1)).each do |i|
              field = self[i][:field]
              ascending = self[i][:ascending]
              break unless comparison.zero?

              value_on_a = ForestAdminDatasourceToolkit::Utils::Record.field_value(a, field)
              value_on_b = ForestAdminDatasourceToolkit::Utils::Record.field_value(b, field)

              comparison = value_on_a <=> value_on_b
              comparison = 1 if comparison.nil?
              comparison *= -1 unless ascending
            end

            comparison
          end
        end
      end
    end
  end
end
