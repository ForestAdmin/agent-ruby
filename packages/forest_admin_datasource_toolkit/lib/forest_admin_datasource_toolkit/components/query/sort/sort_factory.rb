module ForestAdminDatasourceToolkit
  module Components
    module Query
      module Sort
        class SortFactory
          def self.by_primary_keys(collection)
            Sort.new(
              ForestAdminDatasourceToolkit::Utils::Schema.primary_keys(collection)
                                                         .map { |pk| { field: pk, ascending: true } }
            )
          end
        end
      end
    end
  end
end
