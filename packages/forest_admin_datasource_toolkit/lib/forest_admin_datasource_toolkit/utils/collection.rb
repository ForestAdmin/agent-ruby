module ForestAdminDatasourceToolkit
  module Utils
    class Collection
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminDatasourceToolkit::Schema
      include ForestAdminDatasourceToolkit::Schema::Relations
      include ForestAdminDatasourceToolkit::Exceptions

      def self.get_inverse_relation(collection, relation_name)
        relation_field = collection.schema[:fields][relation_name]
        foreign_collection = collection.datasource.get_collection(relation_field.foreign_collection)
        polymorphic_relations = %w[PolymorphicOneToOne PolymorphicOneToMany]

        inverse = foreign_collection.schema[:fields].select do |_name, field|
          if polymorphic_relations.include?(relation_field.type)
            field.is_a?(PolymorphicManyToOneSchema) &&
              field.foreign_collections.include?(collection.name)
          else
            field.is_a?(RelationSchema) &&
              field.foreign_collection == collection.name &&
              (
                (field.is_a?(ManyToManySchema) && relation_field.is_a?(ManyToManySchema) &&
                  many_to_many_inverse?(field, relation_field)) ||
                  (field.is_a?(ManyToOneSchema) &&
                    (relation_field.type == OneToOneSchema || relation_field.is_a?(OneToManySchema)) &&
                    many_to_one_inverse?(field, relation_field)) ||
                  ((field.is_a?(OneToOneSchema) || field.is_a?(OneToManySchema)) &&
                    relation_field.is_a?(ManyToOneSchema) && other_inverse?(field, relation_field))
              )
          end
        end.keys.first

        inverse || nil
      end

      def self.many_to_many_inverse?(field, relation_field)
        field.is_a?(ManyToManySchema) &&
          relation_field.is_a?(ManyToManySchema) &&
          field.origin_key == relation_field.foreign_key &&
          field.through_collection == relation_field.through_collection &&
          field.foreign_key == relation_field.origin_key
      end

      def self.many_to_one_inverse?(field, relation_field)
        field.is_a?(ManyToOneSchema) &&
          (relation_field.is_a?(OneToManySchema) ||
            relation_field.is_a?(OneToOneSchema)) &&
          field.foreign_key == relation_field.origin_key
      end

      def self.other_inverse?(field, relation_field)
        (field.is_a?(OneToManySchema) || field.is_a?(OneToOneSchema)) &&
          relation_field.is_a?(ManyToOneSchema) &&
          field.origin_key == relation_field.foreign_key
      end

      def self.get_field_schema(collection, field_name)
        fields = collection.schema[:fields]
        unless field_name.include?(':')
          raise ForestException, "Column not found #{collection.name}.#{field_name}" unless fields.key?(field_name)

          return fields[field_name]
        end

        association_name = field_name.split(':')[0]
        relation_schema = fields[association_name]

        raise ForestException, "Relation not found #{collection.name}.#{association_name}" unless relation_schema

        if relation_schema.type != 'ManyToOne' && relation_schema.type != 'OneToOne'
          raise ForestException, "Unexpected field type #{relation_schema.type}: #{collection.name}.#{association_name}"
        end

        get_field_schema(
          collection.datasource.get_collection(relation_schema.foreign_collection), field_name.split(':')[1..].join(':')
        )
      end

      def self.get_value(collection, caller, id, field)
        if id.is_a? Array
          index = Schema.primary_keys(collection).index(field)

          return id[index] if index
        elsif Schema.primary_keys(collection).include?(field)
          return id[field]
        end

        record = collection.list(
          caller,
          ForestAdminDatasourceToolkit::Components::Query::Filter.new(condition_tree: ConditionTree::ConditionTreeFactory.match_ids(collection, [id])),
          Projection.new([field])
        )

        record[field]
      end

      def self.get_through_target(collection, relation_name)
        relation = collection.schema[:fields][relation_name]
        raise ForestException, 'Relation must be many to many' unless relation.is_a?(ManyToManySchema)

        through_collection = collection.datasource.get_collection(relation.through_collection)
        through_collection.schema[:fields].select do |field_name, field|
          if field.is_a?(ManyToOneSchema) &&
             field.foreign_collection == relation.foreign_collection &&
             field.foreign_key == relation.foreign_key &&
             field.foreign_key_target == relation.foreign_key_target
            return field_name
          end
        end

        nil
      end

      def self.get_through_origin(collection, relation_name)
        relation = collection.schema[:fields][relation_name]
        raise ForestException, 'Relation must be many to many' unless relation.is_a?(ManyToManySchema)

        through_collection = collection.datasource.get_collection(relation.through_collection)
        through_collection.schema[:fields].select do |field_name, field|
          if field.is_a?(ManyToOneSchema) &&
             field.foreign_collection == collection.name &&
             field.foreign_key == relation.origin_key &&
             field.foreign_key_target == relation.origin_key_target
            return field_name
          end
        end

        nil
      end

      def self.list_relation(collection, id, relation_name, caller, foreign_filter, projection)
        relation = collection.schema[:fields][relation_name]
        foreign_collection = collection.datasource.get_collection(relation.foreign_collection)

        if relation.is_a?(ManyToManySchema) && foreign_filter.nestable?
          foreign_relation = get_through_target(collection, relation_name)

          if foreign_relation
            through_collection = collection.datasource.get_collection(relation.through_collection)
            records = through_collection.list(
              caller,
              FilterFactory.make_through_filter(collection, id, relation_name, caller, foreign_filter),
              projection.nest(prefix: foreign_relation)
            )

            return records.map { |r| r[foreign_relation] }
          end
        end

        foreign_collection.list(
          caller,
          FilterFactory.make_foreign_filter(collection, id, relation_name, caller, foreign_filter),
          projection
        )
      end

      def self.aggregate_relation(collection, id, relation_name, caller, foreign_filter, aggregation, limit = nil)
        relation = collection.schema[:fields][relation_name]
        foreign_collection = collection.datasource.get_collection(relation.foreign_collection)

        if relation.is_a?(ManyToManySchema) && foreign_filter.nestable?
          foreign_relation = get_through_target(collection, relation_name)
          if foreign_relation
            through_collection = collection.datasource.get_collection(relation.through_collection)

            return through_collection.aggregate(
              caller,
              FilterFactory.make_through_filter(collection, id, relation_name, caller, foreign_filter),
              aggregation,
              limit
            )
          end
        end

        foreign_collection.aggregate(
          caller,
          FilterFactory.make_foreign_filter(collection, id, relation_name, caller, foreign_filter),
          aggregation,
          limit
        )
      end
    end
  end
end
