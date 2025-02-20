module ForestAdminDatasourceMongoid
  class OptionsParser
    def self.parse_options(model, options)
      schema = ForestAdminDatasourceMongoid::Utils::Schema::MongoidSchema.from_model(model)

      case options[:flatten_mode]
      when 'manual'
        get_manual_flatten_options(schema, options, model.name)
      when 'none'
        { as_fields: [], as_models: [] }
      else
        get_auto_flatten_options(schema)
      end
    end

    class << self
      private

      def get_auto_flatten_options(schema)
        forbidden_paths = schema.list_paths_matching(->(_, s) { !can_be_flattened(s) })

        # Split on all arrays of objects and arrays of references.
        as_models = schema.list_paths_matching(proc do |field, path_schema|
          path_schema.is_array &&
            (!path_schema.is_leaf ||
              (path_schema.schema_node&.options.is_a?(Hash) && path_schema.schema_node.options[:ref])) &&
            forbidden_paths.none? { |p| field == p || field.start_with?("#{p}.") }
        end).sort

        # flatten all fields which are nested
        as_fields = schema.list_paths_matching(proc do |field, path_schema|
          # on veut flatten si on est à plus de 1 niveau de profondeur par rapport au asModels
          min_distance = field.split('.').length

          as_models.each do |as_model|
            if field.start_with?("#{as_model}.")
              distance = field.split('.').length - as_model.split('.').length
              min_distance = distance if distance < min_distance
            end
          end

          !as_models.include?(field) && path_schema.is_leaf && min_distance > 1 && forbidden_paths.none? do |p|
            field.start_with?("#{p}.")
          end
        end)

        { as_fields: as_fields, as_models: as_models }
      end

      def can_be_flattened(schema)
        return true if schema.is_leaf

        !schema.fields.empty?
      end

      def get_manual_flatten_options(schema, options, model_name)
        as_models = (options[:flatten_options]&.[](model_name)&.[](:as_models) || [])
                    .map { |f| f.tr(':', '.') }
                    .sort

        as_fields = (options[:flatten_options]&.[](model_name)&.[](:as_fields) || [])
                    .flat_map do |item|
                      field = (item.is_a?(String) ? item : item[:field]).tr(':', '.')
                      level = item.is_a?(String) ? 99 : item[:level]
                      sub_schema = schema.get_sub_schema(field)

                      if sub_schema.is_leaf
                        [field]
                      else
                        sub_schema.list_fields(level).map { |f| "#{field}.#{f}" }
                      end
                    end
        as_fields = as_fields.reject { |f| as_models.include?(f) }.sort

        { as_fields: as_fields, as_models: as_models }
      end
    end
  end
end
