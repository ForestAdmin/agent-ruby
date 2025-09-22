require 'spec_helper'

module ForestAdminDatasourceCustomizer
  module Decorators
    module Schema
      describe SchemaCollectionDecorator do
        subject(:schema_collection_decorator) { described_class }

        it 'overwrites fields from the schema' do
          collection = ForestAdminDatasourceToolkit::Collection.new(nil, 'test')
          collection.schema[:countable] = true

          decorator = schema_collection_decorator.new(collection, nil)
          decorator.override_schema(countable: false)

          expect(collection.schema[:countable]).to be true
          expect(decorator.schema[:countable]).to be false
        end
      end
    end
  end
end
