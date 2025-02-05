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
            return unflatten(step[:as_fields]) if index.zero?

            local_schema = schema.get_sub_schema(step[:prefix])
            relative_prefix = if stack[index - 1][:prefix].nil?
                                step[:prefix]
                              else
                                step[:prefix][stack[index - 1][:prefix].length + 1..]
                              end

            [
              *(if local_schema.is_array
                  reparent_array(relative_prefix,
                                 local_schema.is_leaf)
                else
                  reparent_object(relative_prefix,
                                  local_schema.is_leaf)
                end),
              *unflatten(step[:as_fields])
            ]
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
                        'parentId' => '$_id',
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
                        'parentId' => '$_id',
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

          unflatten_results = []
          add_fields = as_fields.map { |f| [f.gsub('.', '@@@'), "$#{f}"] }
          # DocumentDB limits the addFields stage to 30 fields.
          chunk_size = 30

          # TODO: refactor if/else
          if add_fields.length > chunk_size
            (0..(add_fields.length - 1).step(chunk_size)).each do |i|
              chunk = add_fields.slice(i..i + chunk_size)
              unflatten_results << { '$addFields' => chunk }
            end
          else
            unflatten_results << { '$addFields' => add_fields.to_h }
          end

          unflatten_results << { '$project' => as_fields.to_h { |f| [f, 0] } }

          unflatten_results
        end
      end
    end
  end
end
