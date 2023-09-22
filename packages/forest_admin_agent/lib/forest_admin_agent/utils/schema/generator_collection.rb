module ForestAdminAgent
  module Utils
    module Schema
      class GeneratorCollection
        private_class_method :build_fields
        def self.build_schema(collection)
          {
            actions: {},
            fields: build_fields(collection),
            icon: nil,
            integration: nil,
            isReadOnly: false,
            isSearchable: true,
            isVirtual: false,
            name: collection.name,
            onlyForRelationships: false,
            paginationType: 'page',
            segments: {}
          }
        end

        def self.build_fields(collection)
          collection.fields
                    .map { |name, _field| GeneratorField.build_schema(collection, name) }
                    .sort_by { |v| v[:field] }
        end
      end
    end
  end
end
