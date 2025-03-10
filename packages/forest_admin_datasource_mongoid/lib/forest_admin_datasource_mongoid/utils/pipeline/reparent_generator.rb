module ForestAdminDatasourceMongoid
  module Utils
    module Pipeline
      # Generate pipeline to query submodels.
      # The operations make rotations in the documents so that the root is changed to the submodel
      # without loosing the parent (which may be needed later on).
      class ReparentGenerator
        include Utils::Schema

        def self.reparent(model, stack)
          schema = MongoidSchema.from_model(model)

          stack.flat_map.with_index do |step, index|
            # If this is the first step in the stack and there are no fields to flatten, return an empty list
            next [] if index.zero? && step[:as_fields].empty?
            # If this is the first step in the stack, only flatten the provided fields without reparenting
            next unflatten(step[:as_fields]) if index.zero?

            local_schema = schema.get_sub_schema(step[:prefix])
            relative_prefix = if stack[index - 1][:prefix].nil?
                                step[:prefix]
                              else
                                step[:prefix][stack[index - 1][:prefix].length + 1..]
                              end

            result = if local_schema.is_array
                       reparent_array(relative_prefix, local_schema.is_leaf)
                     else
                       reparent_object(relative_prefix, local_schema.is_leaf)
                     end

            [*result, *unflatten(step[:as_fields])]
          end
        end

        def self.reparent_array(prefix, in_doc)
          [
            { '$unwind' => { 'path' => "$#{prefix}", 'includeArrayIndex' => 'index' } },
            {
              '$replaceRoot' => {
                'newRoot' => {
                  '$mergeObjects' => [
                    in_doc ? { 'content' => "$#{prefix}" } : "$#{prefix}",
                    ConditionGenerator.tag_record_if_not_exist(
                      prefix,
                      {
                        '_id' => { '$concat' => [{ '$toString' => '$_id' }, ".#{prefix}.",
                                                 { '$toString' => '$index' }] },
                        'parent_id' => '$_id',
                        'parent' => '$$ROOT'
                      }
                    )
                  ]
                }
              }
            }
          ]
        end

        def self.reparent_object(prefix, in_doc)
          [
            {
              '$replaceRoot' => {
                'newRoot' => {
                  '$mergeObjects' => [
                    in_doc ? { 'content' => "$#{prefix}" } : "$#{prefix}",
                    ConditionGenerator.tag_record_if_not_exist(
                      prefix,
                      {
                        '_id' => { '$concat' => [{ '$toString' => '$_id' }, ".#{prefix}"] },
                        'parent_id' => '$_id',
                        'parent' => '$$ROOT'
                      }
                    )
                  ]
                }
              }
            }
          ]
        end

        def self.unflatten(as_fields)
          return [] if as_fields.empty?

          chunk_size = 30
          add_fields = as_fields.map { |f| [f.gsub('.', '@@@'), "$#{f}"] }

          # MongoDB (DocumentDB) enforces a limit of 30 fields per $addFields stage.
          # We split the list into chunks of 30 to prevent errors.
          unflatten_results = add_fields.each_slice(chunk_size).map { |chunk| { '$addFields' => chunk.to_h } }

          unflatten_results << { '$project' => as_fields.to_h { |f| [f, 0] } }
        end
      end
    end
  end
end
