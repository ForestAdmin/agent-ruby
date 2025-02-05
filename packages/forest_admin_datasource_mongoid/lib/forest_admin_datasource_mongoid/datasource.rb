require 'mongo'
require 'mongoid'

module ForestAdminDatasourceMongoid
  class Datasource < ForestAdminDatasourceToolkit::Datasource
    include Utils::Helpers

    attr_reader :models

    def initialize(options: {})
      super()

      if options && !options[:flatten_mode]
        ForestAdminAgent::Facades::Container.logger.log(
          'Warn',
          'Using unspecified flattenMode. ' \
          'Please refer to the documentation to update your code: ' \
          'https://docs.forestadmin.com/developer-guide-agents-ruby/data-sources/provided-data-sources/mongoid'
        )
      end

      generate(options)
    end

    private

    def generate(options)
      models = ObjectSpace.each_object(Class).select do |klass|
        klass < Mongoid::Document && klass.name && !klass.name.start_with?('Mongoid::') && !embedded_in_relation?(klass)
      end

      # Create collections (with only many to one relations).
      models.each do |model|
        ForestAdminDatasourceMongoid::Utils::Schema::MongoidSchema.from_model(model)
        options_parser = OptionsParser.parse_options(model, options)

        add_model(model, schema, [], nil, options_parser[:as_fields], options_parser[:as_models])
      end

      # Add one-to-many, one-to-one and many-to-many relations.
      # RelationGenerator.addImplicitRelations(this.collections);
    end

    def add_model(
      model,
      schema,
      stack, # current only
      prefix, # prefix that we should handle in this recursion
      as_fields, # current + children
      as_models
    ) # current + children
      local_as_fields = as_fields.filter { |f| as_models.none? { |i| f.start_with?("#{i}.") } }
      local_as_models = as_models.filter { |f| as_models.none? { |i| f.start_with?("#{i}.") } }
      # peut etre faut faire un union parce qu'on pige rien ici de ce merdier
      local_stack = stack.union([{ prefix: prefix, as_fields: local_as_fields, as_models: local_as_models }])

      add_collection(Collection.new(self, model, local_stack))

      local_as_models.each do |name|
        sub_prefix = prefix ? "#{prefix}.#{name}" : name
        sub_as_fields = unnest(as_fields, name)
        sub_as_models = unnest(as_models, name)

        add_model(model, schema, local_stack, sub_prefix, sub_as_fields, sub_as_models)
      end
    end

    def check_as_fields(schema, prefix, local_as_fields)
      local_schema = schema.get_sub_schema(prefix)
      local_as_fields.each do |field|
        name = prefix ? "#{prefix}.#{field}" : field

        if !field.include?('.') && prefix
          raise ForestAdminDatasourceToolkit::Exceptions::ForestException,
                "asFields contains '#{name}', which can't be flattened further because " \
                "asModels contains '#{prefix}', so it is already at the root of a collection."
        end

        unless field.include?('.')
          raise ForestAdminDatasourceToolkit::Exceptions::ForestException,
                "asFields contains '${name}', which can't be flattened because it is already at  " \
                'the root of the model.'
        end

        next unless contains_intermediary_array(local_schema, field)

        raise ForestAdminDatasourceToolkit::Exceptions::ForestException,
              "asFields contains '${name}', " \
              "which can't be moved to the root of the model, because it is inside of an array. " \
              'Either add all intermediary arrays to asModels, or remove it from asFields.'
      end
    end

    def check_as_models(schema, prefix, local_as_models)
      local_schema = schema.get_sub_schema(prefix)

      local_as_models.each do |field|
        name = prefix ? "#{prefix}.#{field}" : field

        next unless contains_intermediary_array(local_schema, field)

        raise ForestAdminDatasourceToolkit::Exceptions::ForestException,
              "asModels contains '#{name}', " \
              "which can't be transformed into a model, because it is inside of an array. " \
              'Either add all intermediary arrays to asModels, or remove it from asModels.'
      end
    end

    def contains_intermediary_array(_local_schema, _field)
      index = field.index('.')

      while index != -1
        prefix = field[0, index]

        return true if schema.get_sub_schema(prefix).is_array

        index = field.index('.', index + 1)
      end
    end

    def embedded_in_relation?(klass)
      klass.relations.any? { |_name, association| association.is_a?(Mongoid::Association::Embedded::EmbeddedIn) }
    end
  end
end
