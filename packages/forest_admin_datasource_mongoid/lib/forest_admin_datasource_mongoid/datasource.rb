require 'mongo'
require 'mongoid'

module ForestAdminDatasourceMongoid
  class Datasource < ForestAdminDatasourceToolkit::Datasource
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
        klass < Mongoid::Document && klass.name && !klass.name.start_with?('Mongoid::') # && !embedded_in_relation?(klass)
      end

      # options parser et schema
      models.each do |model|
        ForestAdminDatasourceMongoid::Utils::Schema::MongoidSchema.from_model(model)
        OptionsParser.parse_options(model, options)
      end

      # models.each do |model|
      #   add_collection(Collection.new(self, model))
      # end
    end

    #   private addModel(
    #     model: Model<unknown>,
    #     schema: MongooseSchema,
    #     stack: Stack, // current only
    #     prefix: string | null, // prefix that we should handle in this recursion
    #     asFields: string[], // current + children
    #     asModels: string[], // current + children
    #   ): void {
    #     const localAsFields = asFields.filter(f => !asModels.some(i => f.startsWith(`${i}.`)));
    #     const localAsModels = asModels.filter(f => !asModels.some(i => f.startsWith(`${i}.`)));
    #     const localStack = [...stack, { prefix, asFields: localAsFields, asModels: localAsModels }];
    #
    #     this.checkAsFields(schema, prefix, localAsFields);
    #     this.checkAsModels(schema, prefix, localAsModels);
    #     this.addCollection(new MongooseCollection(this, model, localStack));
    #
    #     for (const name of localAsModels) {
    #       const subPrefix = prefix ? `${prefix}.${name}` : name;
    #       const subAsFields = unnest(asFields, name);
    #       const subAsModels = unnest(asModels, name);
    #
    #       this.addModel(model, schema, localStack, subPrefix, subAsFields, subAsModels);
    #     }
    #   }

    def add_model(
      _model,
      _schema,
      stack, # current only
      prefix, # prefix that we should handle in this recursion
      as_fields, # current + children
      as_models
    ) # current + children
      local_as_fields = as_fields.filter { |f| as_models.none? { |i| f.start_with?("#{i}.") } }
      local_as_models = as_models.filter { |f| as_models.none? { |i| f.start_with?("#{i}.") } }
      # peut etre faut faire un union parce qu'on pige rien ici de ce merdier
      stack + [{ prefix: prefix, as_fields: local_as_fields, as_models: local_as_models }]
    end

    # TODO: REMOVE ??
    # def embedded_in_relation?(klass)
    #   klass.relations.any? { |_name, association| association.is_a?(Mongoid::Association::Embedded::EmbeddedIn) }
    # end

    # TODO: REMOVE ??
    # def fetch_primary_key(klass)
    #   primary_key = klass.fields.find { |_, field| field.options[:identity] || field.name == '_id' }&.first
    #   unless primary_key
    #     raise(ForestAdminDatasourceToolkit::Exceptions::ForestException,
    #           "Primary key not found for #{klass.name}")
    #   end
    #
    #   primary_key
    # end
  end
end
