module ForestAdminDatasourceCustomizer
  class CollectionCustomizer
    attr_reader :datasource_customizer, :stack, :name

    def initialize(datasource_customizer, stack, name)
      @datasource_customizer = datasource_customizer
      @stack = stack
      @name = name
    end

    def add_action(name, definition)
      push_customization { @stack.action.get_collection(@name).add_action(name, definition) }
    end

    def schema
      @stack.validation.get_collection(@name).schema
    end

    def collection
      @stack.validation.get_collection(@name)
    end

    def use(plugin, options = [])
      push_customization { plugin.new.run(@datasource_customizer, self, options) }
    end

    def disable_count
      push_customization { @stack.schema.get_collection(@name).override_schema(countable: false) }
    end

    def replace_search(definition)
      push_customization { @stack.search.get_collection(@name).replace_search(definition) }
    end

    def add_field(name, definition)
      push_customization do
        collection_before_relations = @stack.early_computed.get_collection(@name)
        collection_after_relations = @stack.late_computed.get_collection(@name)
        can_be_computed_before_relations = definition.dependencies.all? do |field|
          !ForestAdminDatasourceToolkit::Utils::Collection.get_field_schema(collection_before_relations, field).nil?
        rescue StandardError
          false
        end

        collection = can_be_computed_before_relations ? collection_before_relations : collection_after_relations

        collection.register_computed(name, definition)
      end
    end

    def emulate_field_operator(name, operator)
      push_customization do
        collection = if @stack.early_op_emulate.get_collection(@name).schema[:fields].key?(name)
                       @stack.early_op_emulate.get_collection(@name)
                     else
                       @stack.late_op_emulate.get_collection(@name)
                     end

        collection.emulate_field_operator(name, operator)
      end
    end

    def replace_field_operator(name, operator, &replacer)
      push_customization do
        collection = if @stack.early_op_emulate.get_collection(@name).schema[:fields].key?(name)
                       @stack.early_op_emulate.get_collection(@name)
                     else
                       @stack.late_op_emulate.get_collection(@name)
                     end

        collection.replace_field_operator(name, operator, &replacer)
      end
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

    def add_external_relation(name, definition)
      use(ForestAdminDatasourceCustomizer::Plugins::AddExternalRelation, { name: name }.merge(definition))
    end

    # Add a new validator to the edition form of a given field
    # @param name The name of the field
    # @param operator The validator that you wish to add
    # @param value A configuration value that the validator may need
    # @example
    # .add_field_validation('first_name', Operators::LONGER_THAN, 2)
    def add_field_validation(name, operator, value = nil)
      push_customization do
        @stack.validation.get_collection(@name).add_validation(name, { operator: operator, value: value })
      end
    end

    # Enable sorting on a specific field using emulation.
    # As for all the emulation method, the field sorting will be done in-memory.
    # @param name the name of the field to enable emulation on
    # @example
    # .emulate_field_sorting('fullName')
    def emulate_field_sorting(name)
      push_customization { @stack.sort.get_collection(@name).emulate_field_sorting(name) }
    end

    # Replace an implementation for the sorting.
    # The field sorting will be done by the datasource.
    # @param name the name of the field to enable sort
    # @param equivalent_sort the sort equivalent
    # @example
    # .replace_field_sorting(
    #   'fullName',
    #   [
    #     { field: 'firstName', ascending: true },
    #     { field: 'lastName',  ascending: true },
    #   ]
    # )
    def replace_field_sorting(name, equivalent_sort)
      push_customization { @stack.sort.get_collection(@name).replace_field_sorting(name, equivalent_sort) }
    end

    # Remove fields from the exported schema (they will still be usable within the agent).
    # @param names the names of the field or the relation
    # @example
    # .remove_field('fieldNameToRemove', 'relationNameToRemove')
    def remove_field(*names)
      push_customization do
        collection = @stack.publication.get_collection(@name)
        names.each { |name| collection.change_field_visibility(name, false) }
      end
    end

    # Rename fields from the exported schema.
    # @param current_name the current name of the field or the relation in a given collection
    # @param new_name the new name of the field or the relation
    # @example
    # rename_field('currentFieldOrRelationName', 'newFieldOrRelationName')
    def rename_field(current_name, new_name)
      push_customization { @stack.rename_field.get_collection(@name).rename_field(current_name, new_name) }
    end

    # Replace the write behavior of a field.
    # @param name the name of the field
    # @param definition the function or a value to represent the write behavior
    # @example
    # .replace_field_writing('author_last_name') do
    #   { 'author' => { 'last_name' => value } }
    # end
    def replace_field_writing(name, &definition)
      push_customization { @stack.write.get_collection(@name).replace_field_writing(name, &definition) }
    end

    private

    def push_customization(&customization)
      @stack.queue_customization(customization)
    end

    def push_relation(name, definition)
      push_customization { @stack.relation.get_collection(@name).add_relation(name, definition) }
    end
  end
end
