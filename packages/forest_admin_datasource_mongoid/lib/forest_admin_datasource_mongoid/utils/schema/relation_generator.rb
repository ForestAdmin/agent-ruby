module ForestAdminDatasourceMongoid
  module Utils
    module Schema
      class RelationGenerator
        include ForestAdminDatasourceToolkit::Schema::Relations
        extend ForestAdminDatasourceMongoid::Utils::Helpers

        def self.add_implicit_relations(collections)
          collections.each_value do |collection|
            many_to_ones = collection.schema[:fields].select { |_, f| f.type == 'ManyToOne' }

            many_to_ones.each do |(name, field)|
              add_many_to_one_inverse(collection, name, field)
            end
          end
        end

        # Given any many to one relation, generated while parsing mongoose schema, generate the
        # inverse relationship on the foreignCollection.
        # /!\ The inverse can be a OneToOne, or a ManyToOne
        def self.add_many_to_one_inverse(collection, name, schema)
          if name == 'parent'
            # Create inverse of 'parent' relationship so that the relation name matches the actual name
            # of the data which is stored in the database.
            stack = collection.stack
            prefix = stack[stack.length - 1][:prefix]
            is_array = MongoidSchema.from_model(collection.model).apply_stack(stack).is_array

            type = is_array ? OneToManySchema : OneToOneSchema
            inverse_name = escape(prefix)

            if stack.length > 2
              previous_length = stack[stack.length - 2][:prefix].length + 1
              inverse_name = prefix[previous_length..]
            end
          else
            inverse_name = escape("#{collection.name}_#{name}__inverse")
            type = OneToManySchema
          end

          other_collection = collection.datasource.get_collection(schema.foreign_collection)
          other_collection.schema[:fields][inverse_name] = type.new(
            foreign_collection: collection.name,
            origin_key: schema.foreign_key,
            origin_key_target: schema.foreign_key_target
          )
        end
      end
    end
  end
end
