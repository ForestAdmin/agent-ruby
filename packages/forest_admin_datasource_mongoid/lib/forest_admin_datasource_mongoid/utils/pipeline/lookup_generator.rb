module ForestAdminDatasourceMongoid
  module Utils
    module Pipeline
      class LookupGenerator
        include Utils::Schema

        # Transform a forest admin projection into a mongo pipeline that performs the lookups
        # and transformations to target them
        def self.lookup(model, stack, projection, options)
          schema_stack = stack.each_with_index.reduce([MongoidSchema.from_model(model)]) do |acc, (_, index)|
            [
              *acc,
              MongoidSchema.from_model(model).apply_stack(stack.slice(0..index + 1), skip_as_models: true)
            ]
          end

          lookup_projection(nil, schema_stack.map(&:fields), projection, options)
        end

        def self.lookup_projection(current_path, schema_stack, projection, options)
          pipeline = []
          fields = {}

          projection.relations.each do |name, relation_projection|
            pipeline.push(*lookup_relation(current_path, schema_stack, name, relation_projection, options))
            # pipeline = [*pipeline, *lookup_relation(current_path, schema_stack, name, relation_projection, options)]
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
          models = ObjectSpace
                   .each_object(Class)
                   .select { |klass| klass < Mongoid::Document && klass.name && !klass.name.start_with?('Mongoid::') }
                   .to_h { |klass| [klass.name, klass] }

          as = current_path ? "#{current_path}.#{name}" : name

          last_schema = schema_stack[schema_stack.length - 1]
          previous_schema = schema_stack.slice(0..schema_stack.length - 1)

          return {} if options[:include] && !options[:include].include?(as)
          return {} if options[:exclude]&.include?(as)

          # Native many to one relation
          identifier = '__many_to_one'
          if name.end_with?(identifier)
            foreign_key_name = name[0..(name.length - identifier.length - 1)]
            model = models[last_schema[foreign_key_name].options[:association].class_name]

            from = model.name.gsub('::', '__')
            local_field = current_path ? "#{current_path}.#{foreign_key_name}" : foreign_key_name
            foreign_field = '_id'
            sub_schema = MongoidSchema.from_model(model).fields

            return [
              # Push lookup to pipeline
              { '$lookup' =>
                { 'from' => from, 'localField' => local_field, 'foreignField' => foreign_field, 'as' => as } },
              { '$unwind' => { 'path' => "$#{as}", 'preserveNullAndEmptyArrays' => true } },

              # Recurse to get relations of relations
              *lookup_projection(as, [*schema_stack, sub_schema], projection, options)
            ]
          end

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
