module ForestAdminDatasourceMongoid
  class Collection < ForestAdminDatasourceToolkit::Collection
    include Parser::Column
    include Parser::Validation
    include Parser::Relation
    include ForestAdminDatasourceToolkit::Components::Query
    include Utils::Helpers
    include Utils::Schema
    include Utils::Pipeline
    include Utils::AddNullValues

    attr_reader :model, :stack

    def initialize(datasource, model, stack)
      prefix = stack[stack.length - 1][:prefix]

      @model = model
      @stack = stack
      model_name = format_model_name(@model.name)
      name = escape(prefix ? "#{prefix}.#{model_name}" : model_name)
      super(datasource, name)

      add_fields(FieldsGenerator.build_fields_schema(model, stack))
      # fetch_fields
      # fetch_associations
      enable_count
    end

    def list(_caller, filter, projection)
      projection = projection.union(filter.condition_tree&.projection || [], filter.sort&.projection || [])
      pipeline = [*build_base_pipeline(filter, projection), *ProjectionGenerator.project(projection)]

      add_null_values(replace_mongo_types(model.collection.aggregate(pipeline).to_a), projection)
      # model.unscoped.collection.aggregate(pipeline).to_a
    end

    def aggregate(_caller, filter, aggregation, limit = nil)
      lookup_projection = aggregation.projection.union(filter.condition_tree&.projection || [])
      pipeline = [
        *build_base_pipeline(filter, lookup_projection),
        *GroupGenerator.group(aggregation),
        { '$sort' => { value: -1 } }
      ]
      pipeline << { '$limit' => limit } if limit
      rows = model.collection.aggregate(pipeline).to_a

      replace_mongo_types(rows)
      # Utils::QueryAggregate.new(self, aggregation, filter, limit).get
    end

    def create(_caller, data)
      Utils::MongoidSerializer.new(model.create(data)).to_hash(ProjectionFactory.all(self))
    end

    def update(_caller, filter, data)
      entity = Utils::Query.new(self, nil, filter).build.first
      entity&.update(data)
    end

    def delete(_caller, filter)
      entities = Utils::Query.new(self, nil, filter).build
      entities&.each(&:destroy)
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

    # def fetch_fields
    #   # Standard fields
    #   @model.fields.each do |column_name, column|
    #     field = ForestAdminDatasourceToolkit::Schema::ColumnSchema.new(
    #       column_type: get_column_type(column),
    #       filter_operators: operators_for_column_type(get_column_type(column)),
    #       is_primary_key: column.object_id_field? && column.association.nil?,
    #       is_read_only: false,
    #       is_sortable: true,
    #       default_value: column.object_id_field? ? nil : get_default_value(column),
    #       enum_values: [],
    #       validations: get_validations(column)
    #     )
    #
    #     add_field(column_name, field)
    #   end
    #
    #   # Embedded field (EmbedsMany and EmbedsOne)
    #   get_embedded_fields(@model).each do |column_name, column|
    #     field = ForestAdminDatasourceToolkit::Schema::ColumnSchema.new(
    #       column_type: get_column_type(column),
    #       is_primary_key: false,
    #       is_sortable: false
    #     )
    #     add_field(column_name, field)
    #   end
    # end

    # def fetch_associations
    #   @model.relations.transform_values do |association|
    #     case association
    #     when Mongoid::Association::Referenced::HasMany
    #       if association.polymorphic?
    #         add_field(
    #           association.name.to_s,
    #           ForestAdminDatasourceToolkit::Schema::Relations::PolymorphicOneToManySchema.new(
    #             foreign_collection: format_model_name(association.klass.name),
    #             origin_key: association.foreign_key,
    #             origin_key_target: association.primary_key,
    #             origin_type_field: association.type,
    #             origin_type_value: association.inverse_class_name.constantize
    #           )
    #         )
    #       else
    #         add_field(
    #           association.name.to_s,
    #           ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema.new(
    #             foreign_collection: format_model_name(association.klass.name),
    #             origin_key: association.foreign_key,
    #             origin_key_target: association.primary_key
    #           )
    #         )
    #       end
    #     when Mongoid::Association::Referenced::BelongsTo
    #       if association.polymorphic?
    #         foreign_collections = get_polymorphic_types(association.name)
    #         add_field(
    #           association.name.to_s,
    #           ForestAdminDatasourceToolkit::Schema::Relations::PolymorphicManyToOneSchema.new(
    #             foreign_collections: foreign_collections.keys,
    #             foreign_key: association.foreign_key,
    #             foreign_key_type_field: association.inverse_type,
    #             foreign_key_targets: foreign_collections
    #           )
    #         )
    #         schema[:fields][association.foreign_key].is_read_only = true
    #         schema[:fields][association.inverse_type].is_read_only = true
    #       else
    #         add_field(
    #           association.name.to_s,
    #           ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema.new(
    #             foreign_collection: format_model_name(association.klass.name),
    #             foreign_key: association.foreign_key,
    #             foreign_key_target: association.primary_key
    #           )
    #         )
    #       end
    #     when Mongoid::Association::Referenced::HasOne
    #       if association.polymorphic?
    #         add_field(
    #           association.name.to_s,
    #           ForestAdminDatasourceToolkit::Schema::Relations::PolymorphicOneToOneSchema.new(
    #             foreign_collection: format_model_name(association.klass.name),
    #             origin_key: association.foreign_key,
    #             origin_key_target: association.primary_key,
    #             origin_type_field: association.type,
    #             origin_type_value: association.inverse_class_name.constantize
    #           )
    #         )
    #       else
    #         add_field(
    #           association.name.to_s,
    #           ForestAdminDatasourceToolkit::Schema::Relations::OneToOneSchema.new(
    #             foreign_collection: format_model_name(association.klass.name),
    #             origin_key: association.foreign_key,
    #             origin_key_target: association.primary_key
    #           )
    #         )
    #       end
    #     when Mongoid::Association::Referenced::HasAndBelongsToMany
    #       foreign_key_of_association = association.klass.reflect_on_all_associations.find do |assoc|
    #         assoc.klass == association.inverse_class_name.constantize
    #       end&.foreign_key
    #
    #       add_field(
    #         association.name.to_s,
    #         ForestAdminDatasourceToolkit::Schema::Relations::OneToManySchema.new(
    #           foreign_collection: format_model_name(association.klass.name),
    #           origin_key: foreign_key_of_association,
    #           origin_key_target: association.primary_key
    #         )
    #       )
    #     end
    #   end
    # end
  end
end
