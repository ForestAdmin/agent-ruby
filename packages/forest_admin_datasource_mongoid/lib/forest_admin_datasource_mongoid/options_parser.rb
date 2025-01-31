module ForestAdminDatasourceMongoid
  class OptionsParser
    def self.parse_options(model, options)
      schema = '' # MongoidSchema.from_model(model) TODO

      case options[:flatten_mode]
      when 'auto'
        get_auto_flatten_options(schema)
      when 'manual'
        get_manual_flatten_options(schema, options, model.name)
      when 'none'
        { as_fields: [], as_models: [] }
      else
        get_legacy_flatten_options(schema, options, model.name)
      end
    end

    class << self
      def self.get_auto_flatten_options(schema); end

      def self.get_manual_flatten_options(schema, options, model_name); end

      # if (options?.asModels?.[modelName]) {
      #       // [legacy mode] retro-compatibility when customer provided asModels
      #       const cuts = new Set(options.asModels[modelName].map(f => f.replace(/:/g, '.')));
      #
      #       for (let field of cuts) {
      #         while (field.lastIndexOf('.') !== -1) {
      #           field = field.substring(0, field.lastIndexOf('.'));
      #           cuts.add(field);
      #         }
      #       }
      #
      #       asFields = [];
      #       asModels = [...cuts].sort();
      #     } else {
      #       // [legacy mode] retro-compatibility when customer did not provice anything
      #       asFields = [];
      #       asModels = Object.keys(schema.fields)
      #         .filter(field => schema.fields[field]?.['[]']?.options?.ref)
      #         .sort();
      #     }
      #
      #     return { asFields, asModels };
      def self.get_legacy_flatten_options(_schema, options, model_name); end
    end
  end
end
