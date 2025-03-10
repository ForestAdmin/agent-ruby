module ForestAdminDatasourceMongoid
  module Utils
    module Pipeline
      class FilterGenerator
        include ForestAdminDatasourceToolkit::Components::Query::ConditionTree

        STRING_OPERATORS = [Operators::MATCH, Operators::NOT_CONTAINS, Operators::NOT_I_CONTAINS].freeze

        def self.sort_and_paginate(model, filter)
          sort = compute_sort(filter.sort)

          sort_and_limit = []

          sort_and_limit << { '$sort' => sort } if sort

          if filter.page
            sort_and_limit << { '$skip' => filter.page.offset }
            sort_and_limit << { '$limit' => filter.page.limit }
          end

          return [sort_and_limit, [], []] unless sort

          all_sort_criteria_native = sort.keys.none? do |key|
            !model.fields.key?(key)
          end

          # if sort applies to native fields and no filters are applied (very common case)
          # we apply pre-sort + limit at the beginning of the pipeline (to improve perf)
          return [sort_and_limit, [], []] if all_sort_criteria_native && filter.condition_tree.nil?

          all_condition_tree_keys_native = filter.condition_tree&.projection&.none? do |key|
            !model.fields.key?(key)
          end

          # if filters apply to native fields only, we can apply the sort right after filtering
          return [[], sort_and_limit, []] if all_sort_criteria_native && all_condition_tree_keys_native

          # if sorting apply to relations, it is safer to do it at the end of the pipeline
          [[], [], sort_and_limit]
        end

        def self.filter(model, stack, filter)
          fields = []
          tree = filter.condition_tree
          match = compute_match(model, stack, tree, fields)

          pipeline = []
          pipeline << compute_fields(fields) unless fields.empty?
          pipeline << { '$match' => match } if match

          pipeline
        end

        def self.list_relations_used_in_filter(filter)
          fields = Set.new

          filter.sort&.each do |clause|
            next unless clause[:field].include?(':') # only relations (fields containing ':')

            list_paths(clause[:field]).each do |field|
              parts = field.split('.') # Split into nested levels ("author.country.name"→ ["author", "country", "name"])

              (1...parts.length).each do |i|
                parent_field = parts[0...i].join('.')
                fields.add(parent_field)
              end
            end
          end

          list_fields_used_in_filter_tree(filter.condition_tree, fields)

          fields.to_a
        end

        def self.list_fields_used_in_filter_tree(condition_tree, fields)
          if condition_tree.is_a? Nodes::ConditionTreeBranch
            condition_tree.conditions.each { |condition| list_fields_used_in_filter_tree(condition, fields) }
          elsif condition_tree&.field&.include?(':')
            list_paths(condition_tree.field).each { |field| fields << field }
          end
        end

        def self.list_paths(field)
          parts = field.split(':')

          parts.slice(0..)&.map&.with_index { |_, index| parts.slice(0, index + 1).join('.') }
        end

        def self.compute_sort(sort)
          return if sort.nil? || sort.empty?

          result = {}

          sort.each do |clause|
            formatted_field = format_nested_field_path(clause[:field])
            result[formatted_field] = clause[:ascending] ? 1 : -1
          end

          result
        end

        def self.format_nested_field_path(field)
          field.tr(':', '.')
        end

        def self.compute_match(model, stack, tree, fields)
          schema = Utils::Schema::MongoidSchema.from_model(model).apply_stack(stack, skip_as_models: true)

          if tree.is_a? Nodes::ConditionTreeBranch
            # to check
            return {
              "$#{tree.aggregator.downcase}" => tree.conditions.map do |condition|
                compute_match(model, stack, condition, fields)
              end
            }
          end

          if tree.is_a? Nodes::ConditionTreeLeaf
            value = format_and_cast_leaf_value(schema, tree, fields)
            condition = build_match_condition(tree.operator, value)

            return { format_nested_field_path(tree.field) => condition }
          end

          nil
        end

        def self.format_and_cast_leaf_value(schema, leaf, fields)
          value = leaf.value
          leaf = leaf.override(field: format_nested_field_path(leaf.field))
          is_array, instance = get_field_metadata(schema, leaf.field)

          if is_array
            if instance == Date && value.is_a?(Array) && value.all? { |v| valid_iso_date?(v) }
              value = value.map { |v| Date.parse(v) }
            elsif instance == BSON::ObjectId && value.is_a?(Array) && value.all? { |v| BSON::ObjectId.legal?(v) }
              value = value.map { |id| BSON::ObjectId.from_string(id) }
            end
          elsif instance == BSON::ObjectId
            if STRING_OPERATORS.include?(leaf.operator)
              fields << leaf.field
              leaf.override(field: format_string_field_name(leaf.field))
            elsif value.is_a?(Array) && value.all? { |v| BSON::ObjectId.legal?(v) }
              value = value.map { |id| BSON::ObjectId.from_string(id) }
            elsif BSON::ObjectId.legal?(value)
              value = BSON::ObjectId.from_string(value)
            end
          elsif instance == Date && valid_iso_date?(value)
            value = Date.parse(value)
          end

          value
        end

        def self.build_match_condition(operator, value)
          case operator
          when Operators::GREATER_THAN
            { '$gt' => value }
          when Operators::LESS_THAN
            { '$lt' => value }
          when Operators::EQUAL
            { '$eq' => value }
          when Operators::NOT_EQUAL
            { '$ne' => value }
          when Operators::IN
            { '$in' => value }
          when Operators::INCLUDES_ALL
            { '$all' => value }
          when Operators::NOT_CONTAINS
            { '$not' => Regexp.new("^.*#{value}.*$") }
          when Operators::NOT_I_CONTAINS
            { '$not' => Regexp.new("^.*#{value}.*$", 'i') }
          when Operators::MATCH
            { '$regex' => value }
          when Operators::PRESENT
            { '$exists' => true, '$ne' => null }
          else
            raise ForestAdminDatasourceToolkit::Exceptions::ForestException, "Unsupported '#{operator}' operator"
          end
        end

        def self.compute_fields(fields)
          fields.reduce({ '$addFields' => {} }) do |computed, field|
            string_field = format_string_field_name(field)
            computed['$addField'][string_field] = { '$toString' => "$#{field}" }
          end
        end

        def self.format_string_field_name(field)
          parts = field.split('.')
          parts << "string_#{parts.pop}"

          parts.join('.')
        end

        def self.get_field_metadata(schema, field)
          begin
            sub_schema = schema.get_sub_schema(field)
            is_array = sub_schema.is_array
            instance = sub_schema.schema_type.type
          rescue StandardError
            is_array = false
            instance = 'String'
          end

          [is_array, instance]
        end

        def self.valid_iso_date?(value)
          DateTime.iso8601(value)
          true
        rescue ArgumentError
          false
        end
      end
    end
  end
end
