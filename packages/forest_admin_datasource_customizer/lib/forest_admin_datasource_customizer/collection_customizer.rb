module ForestAdminDatasourceCustomizer
  class CollectionCustomizer
    attr_reader :datasource_customizer, :stack, :name

    def initialize(datasource_customizer, stack, name)
      @datasource_customizer = datasource_customizer
      @stack = stack
      @name = name
    end

    def add_action(name, definition)
      push_customization(
        proc { @stack.action.get_collection(@name).add_action(name, definition) }
      )
    end

    def schema
      @stack.datasource.get_collection(@name).schema
    end

    def collection
      @stack.datasource.get_collection(@name)
    end

    def use(plugin, options = [])
      push_customization(
        proc { plugin.run(@datasource_customizer, self, options) }
      )
    end

    def disable_count
      push_customization(
        -> { @stack.schema.get_collection(@name).override_schema(countable: false) }
      )
    end

    def replace_search(definition)
      push_customization(
        proc { @stack.search.get_collection(@name).replace_search(definition) }
      )
    end

    def add_field(name, definition)
      push_customization(
        proc {
          collection_before_relations = @stack.early_computed.get_collection(@name)
          collection_after_relations = @stack.late_computed.get_collection(@name)
          can_be_computed_before_relations = definition.dependencies.all? do |field|
            !ForestAdminDatasourceToolkit::Utils::Collection.get_field_schema(collection_before_relations, field).nil?
          rescue StandardError
            false
          end

          collection = can_be_computed_before_relations ? collection_before_relations : collection_after_relations

          collection.register_computed(name, definition)
        }
      )
    end

    # Add a many to one relation to the collection
    # @param name name of the new relation
    # @param foreign_collection name of the targeted collection
    # @param options extra information about the relation
    # @example
    # books.add_many_to_one_relation('my_author', 'persons', { foreign_key: 'author_id' })
    def add_many_to_one_relation(name, foreign_collection, options = {})
      push_relation(name, {
                      type: 'ManyToOne',
                      foreign_collection: foreign_collection,
                      foreign_key: options[:foreign_key],
                      foreign_key_target: options[:foreign_key_target]
                    })
    end

    # Add a one to many relation to the collection
    # @param name name of the new relation
    # @param foreign_collection name of the targeted collection
    # @param options extra information about the relation
    # @example
    # persons.add_one_to_many_relation('written_books', 'books', { origin_key: 'author_id' })
    def add_one_to_many_relation(name, foreign_collection, options = {})
      push_relation(name, {
                      type: 'OneToMany',
                      foreign_collection: foreign_collection,
                      origin_key: options[:origin_key],
                      origin_key_target: options[:origin_key_target]
                    })
    end

    # Add a one to one relation to the collection
    # @param name name of the new relation
    # @param foreign_collection name of the targeted collection
    # @param options extra information about the relation
    # @example
    # persons.add_one_to_one_relation('best_friend', 'persons', { origin_key: 'best_friend_id' })
    def add_one_to_one_relation(name, foreign_collection, options = {})
      push_relation(name, {
                      type: 'OneToOne',
                      foreign_collection: foreign_collection,
                      origin_key: options[:origin_key],
                      origin_key_target: options[:origin_key_target]
                    })
    end

    # Add a many to many relation to the collection
    # @param name name of the new relation
    # @param foreign_collection name of the targeted collection
    # @param through_collection name of the intermediary collection
    # @param options extra information about the relation
    # @example
    # dvds.add_many_to_many_relation('rentals_of_this_dvd', 'rentals', 'dvd_rentals', {
    #  origin_key: 'dvd_id',
    # foreign_key: 'rental_id'
    # })
    def add_many_to_many_relation(name, foreign_collection, through_collection, options = {})
      push_relation(name, {
                      type: 'ManyToMany',
                      foreign_collection: foreign_collection,
                      through_collection: through_collection,
                      origin_key: options[:origin_key],
                      origin_key_target: options[:origin_key_target],
                      foreign_key: options[:foreign_key],
                      foreign_key_target: options[:foreign_key_target]
                    })
    end

    private

    def push_customization(customization)
      @stack.queue_customization(customization)
    end

    def push_relation(name, definition)
      push_customization(
        proc { @stack.relation.get_collection(@name).add_relation(name, definition) }
      )
    end
  end
end
