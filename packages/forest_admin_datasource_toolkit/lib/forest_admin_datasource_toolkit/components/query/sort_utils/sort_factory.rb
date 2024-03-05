module ForestAdminDatasourceToolkit
  module Components
    module Query
      module SortUtils
        class SortFactory
          def self.by_primary_keys(collection)
            ForestAdminDatasourceToolkit::Components::Query::Sort.new(
              ForestAdminDatasourceToolkit::Utils::Schema.primary_keys(collection)
                                                         .map { |pk| { field: pk, ascending: true } }
            )
          end
        end
      end
    end
  end
end
