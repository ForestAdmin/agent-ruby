module ForestAdminAgent
  module Utils
    module Schema
      class ForestValueConverter
        def self.value_to_forest(field)
          if ActionFields.enum_field?(field)
            return field.enum_values.include?(field.value) ? field.value : nil
          end

          return field.value.select { |v| field.enum_values.include?(v) } if ActionFields.enum_list_field?(field)

          return field.value.join('|') if ActionFields.collection_field?(field)

          # return make_data_uri(field.value) if ActionFields.file_field?(field)
          #
          # return value.map { |f| make_data_uri(f) } if ActionFields.file_list_field?(field)

          value
        end

        def self.make_data_uri(file)
          # TODO: to implement
        end

        def self.parse_data_uri(file)
          # TODO: to implement
        end
      end
    end
  end
end
