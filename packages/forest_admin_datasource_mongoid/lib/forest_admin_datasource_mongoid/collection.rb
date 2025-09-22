module ForestAdminDatasourceMongoid
  class Collection < ForestAdminDatasourceToolkit::Collection
    include ForestAdminDatasourceToolkit::Components::Query
    include ForestAdminDatasourceToolkit::Exceptions
    include Parser::Column
    include Parser::Relation
    include Parser::Validation
    include Utils::AddNullValues
    include Utils::Schema
    include Utils::Pipeline
    include Utils::Helpers

    attr_reader :model, :stack

    def initialize(datasource, model, stack)
      prefix = stack[stack.length - 1][:prefix]

      @model = model
      @stack = stack
      model_name = format_model_name(@model.name)
      name = escape(prefix ? "#{model_name}.#{prefix}" : model_name)
      super(datasource, name)

      add_fields(FieldsGenerator.build_fields_schema(model, stack))
      enable_count
    end

    def list(_caller, filter, projection)
      projection = projection.union(filter.condition_tree&.projection || [], filter.sort&.projection || [])
      pipeline = [*build_base_pipeline(filter, projection), *ProjectionGenerator.project(projection)]
      add_null_values(replace_mongo_types(model.unscoped.collection.aggregate(pipeline).to_a), projection)
    end

    def aggregate(_caller, filter, aggregation, limit = nil)
      lookup_projection = aggregation.projection.union(filter.condition_tree&.projection || [])
      pipeline = [
        *build_base_pipeline(filter, lookup_projection),
        *GroupGenerator.group(aggregation),
        { '$sort' => { value: -1 } }
      ]
      pipeline << { '$limit' => limit } if limit
      rows = model.unscoped.collection.aggregate(pipeline).to_a

      replace_mongo_types(rows)
    end

    def create(caller, data)
      handle_validation_error { _create(caller, data) }
    end

    def _create(_caller, flat_data)
      as_fields = @stack[stack.length - 1][:as_fields]
      data = unflatten_record(flat_data, as_fields)
      inserted_record = @model.create(data)

      { '_id' => inserted_record.attributes['_id'], **flat_data }
    end

    def update(caller, filter, data)
      handle_validation_error { _update(caller, filter, data) }
    end

    def _update(_caller, filter, flat_patch)
      as_fields = @stack[stack.length - 1][:as_fields]
      patch = unflatten_record(flat_patch, as_fields, patch_mode: true)
      formatted_patch = reformat_patch(patch)

      records = list(nil, filter, Projection.new(['_id']))
      ids = records.map { |record| record['_id'] }

      if ids.length > 1
        @model.where(_id: ids).update_all(formatted_patch)
      else
        @model.find(ids.first).update(formatted_patch)
      end
    end

    def delete(caller, filter)
      handle_validation_error { _delete(caller, filter) }
    end

    def _delete(_caller, filter)
      records = list(nil, filter, Projection.new(['_id']))
      ids = records.map { |record| record['_id'] }

      @model.where(_id: ids).delete_all
    end

    private

    def build_base_pipeline(filter, projection)
      fields_used_in_filters = FilterGenerator.list_relations_used_in_filter(filter)

      pre_sort_and_paginate,
        sort_and_paginate_post_filtering,
        sort_and_paginate_all = FilterGenerator.sort_and_paginate(model, filter)

      reparent_stages = ReparentGenerator.reparent(model, stack)

      # For performance reasons, we want to only include the relationships that are used in filters
      # before applying the filters
      lookup_used_in_filters_stage = LookupGenerator.lookup(model, stack, projection,
                                                            { include: fields_used_in_filters })
      filter_stage = FilterGenerator.filter(model, stack, filter)
      # Here are the remaining relationships that are not used in filters. For performance reasons
      # they are computed after the filters.
      lookup_not_filtered_stage = LookupGenerator.lookup(
        model,
        stack,
        projection,
        { exclude: fields_used_in_filters }
      )

      [
        *pre_sort_and_paginate,
        *reparent_stages,
        *lookup_used_in_filters_stage,
        *filter_stage,
        *sort_and_paginate_post_filtering,
        *lookup_not_filtered_stage,
        *sort_and_paginate_all
      ]
    end

    def format_model_name(class_name)
      class_name.gsub('::', '__')
    end

    def handle_validation_error
      yield
    rescue Mongoid::Errors::Validations => e
      raise ForestAdminDatasourceToolkit::Exceptions::ValidationError, e.message
    end
  end
end
