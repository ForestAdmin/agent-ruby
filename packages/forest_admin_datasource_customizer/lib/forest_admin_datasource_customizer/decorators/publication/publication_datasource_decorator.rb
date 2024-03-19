module ForestAdminDatasourceCustomizer
  module Decorators
    module Publication
      class PublicationDatasourceDecorator < ForestAdminDatasourceToolkit::Decorators::DatasourceDecorator
        include ForestAdminDatasourceToolkit::Exceptions
        attr_reader :blacklist

        def initialize(child_datasource)
          super(child_datasource, PublicationCollectionDecorator)
          @blacklist = []
        end

        def collections
          @child_datasource.collections.except(*@blacklist).to_h do |name, _collection|
            [name, get_collection(name)]
          end
        end

        def get_collection(name)
          raise ForestException, "Collection '#{name}' was removed." if @blacklist.include?(name)

          super(name)
        end

        def keep_collections_matching(include = [], exclude = [])
          validate_collection_names(include.to_a + exclude.to_a)

          # List collection we're keeping from the white/black list.
          @child_datasource.collections.each_key do |collection|
            remove_collection(collection) if (include && !include.include?(collection)) || exclude&.include?(collection)
          end
        end

        def remove_collection(collection_name)
          validate_collection_names([collection_name])

          # Delete the collection
          @blacklist << collection_name

          # Tell all collections that their schema is dirty: if we removed a collection, all
          # relations to this collection are now invalid and should be unpublished.
          collections.each_value(&:mark_schema_as_dirty)
        end

        def published?(collection_name)
          !@blacklist.include?(collection_name)
        end

        private

        def validate_collection_names(names)
          names.each { |name| get_collection(name) }
        end
      end
    end
  end
end
