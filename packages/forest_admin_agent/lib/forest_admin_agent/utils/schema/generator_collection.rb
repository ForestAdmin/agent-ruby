module ForestAdminAgent
  module Utils
    module Schema
      class GeneratorCollection
        include ForestAdminDatasourceToolkit::Utils

        def self.build_schema(collection)
          {
            actions: build_actions(collection),
            fields: build_fields(collection),
            icon: nil,
            integration: nil,
            isReadOnly: collection.schema[:fields].all? { |_k, field| field.type != 'Column' || field.is_read_only },
            isSearchable: true,
            isVirtual: false,
            name: collection.name,
            onlyForRelationships: false,
            paginationType: 'page',
            segments: {}
          }
        end

        def self.build_fields(collection)
          fields = collection.schema[:fields].select do |name, _field|
            !ForestAdminDatasourceToolkit::Utils::Schema.foreign_key?(collection, name) ||
              ForestAdminDatasourceToolkit::Utils::Schema.primary_key?(collection, name)
          end

          fields.map { |name, _field| GeneratorField.build_schema(collection, name) }
                .sort_by { |v| v[:field] }
        end

        def self.build_actions(collection)
          if collection.schema[:actions]
            collection.schema[:actions].keys.sort.map { |name| GeneratorAction.build_schema(collection, name) }
          else
            {}
          end
        end
      end
    end
  end
end
