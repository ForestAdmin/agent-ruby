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

        # override get collections(): PublicationCollectionDecorator[] {
        #     return this.childDataSource.collections
        #       .filter(({ name }) => !this.blacklist.has(name))
        #       .map(({ name }) => this.getCollection(name));
        #   }

        def collections
          # @child_datasource.collections.transform_values { |c| get_collection(c.name) }
          @child_datasource.collections.reject { |c| @blacklist.include?(c.name) }.map { |c| get_collection(c.name) }
        end

        def get_collection(name)
          raise ForestException, "Collection '#{name}' was removed." if @blacklist.include?(name)

          super(name)
        end

        def keep_collections_matching(include, exclude)
          validate_collection_names(include.to_a + exclude.to_a)

          # List collection we're keeping from the white/black list.
          @child_datasource.collections.each do |collection|
            if (include && !include.include?(collection.name)) || exclude&.include?(collection.name)
              remove_collection(collection.name)
            end
          end
        end

        def remove_collection(collection_name)
          validate_collection_names([collection_name])

          # Delete the collection
          @blacklist << collection_name

          # Tell all collections that their schema is dirty: if we removed a collection, all
          # relations to this collection are now invalid and should be unpublished.
          collections.each(&:mark_schema_as_dirty)
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
