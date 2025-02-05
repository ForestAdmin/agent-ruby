module ForestAdminDatasourceMongoid
  module Utils
    module Pipeline
      class LookupGenerator
        include Utils::Schema

        # Transform a forest admin projection into a mongo pipeline that performs the lookups
        # and transformations to target them
        def self.lookup(model, stack, projection, options)
          stack.each_with_index.reduce([MongoidSchema.from_model(model)]) do |acc, (_, index)|
            [
              *acc,
              MongoidSchema.from_model(model).apply_stack(stack.slice(0..index + 1), skip_as_models: true)
            ]
          end

          lookup_projection(nil, stack.map { |s| s[:fields] }, projection, options)
        end

        def self.lookup_projection(current_path, schema_stack, projection, options)
          pipeline = []
          fields = {}

          projection.relations.each do |name, relation_projection|
            pipeline << lookup_relation(current_path, schema_stack, name, relation_projection, options)
            fields.merge!(add_fields(name, relation_projection, options))
          end

          pipeline
        end

        def self.add_fields(name, projection, options)
          return {} if options[:include] && !options[:include].include?(name)
          return {} if options[:exclude]&.include?(name)

          projection.filter { |field| field.include?('@@@') }
                    .map { |field_name| "#{name}.#{field_name.tr(":", ".")}" }
                    .each_with_object({}) do |curr, acc|
                      acc[curr] = "$#{curr.tr("@@@", ".")}"
                    end
        end

        def self.lookup_relation(current_path, schema_stack, name, projection, options)
          ObjectSpace.each_object(Class)
                     .select { |klass| klass < Mongoid::Document && klass.name && !klass.name.start_with?('Mongoid::') }
                     .to_h { |klass| [klass.name, klass] }
          as = current_path ? "#{current_path}.#{name}" : name

          last_schema = schema_stack[schema_stack.length - 1]
          previous_schema = schema_stack.slice(0..schema_stack.length - 1)

          return [] if options[:include] && !options[:include].include?(as)
          return [] if options[:exclude]&.include?(as)

          # Native many to one relation
          # TODO
          # if (name.endsWith('__manyToOne')) {
          #       const foreignKeyName = name.substring(0, name.length - '__manyToOne'.length);
          #       const model = models[lastSchema[foreignKeyName].options.ref];
          #
          #       const from = model.collection.collectionName;
          #       const localField = currentPath ? `${currentPath}.${foreignKeyName}` : foreignKeyName;
          #       const foreignField = '_id';
          #
          #       const subSchema = MongooseSchema.fromModel(model).fields;
          #
          #       return [
          #         // Push lookup to pipeline
          #         { $lookup: { from, localField, foreignField, as } },
          #         { $unwind: { path: `$${as}`, preserveNullAndEmptyArrays: true } },
          #
          #         // Recurse to get relations of relations
          #         ...this.lookupProjection(models, as, [...schemaStack, subSchema], subProjection, options),
          #       ];
          #     }

          # inverse of fake relation
          if name == 'parent' && !previous_schema.empty?
            return lookup_projection(as, previous_schema, projection, options)
          end

          # fake relation
          return lookup_projection(as, [*schema_stack, last_schema[name]], projection, options) if last_schema[name]

          # We should have handled all possible cases.
          raise ForestAdminDatasourceToolkit::Exceptions::ForestException, "Unexpected relation: '#{name}'"
        end
      end
    end
  end
end
