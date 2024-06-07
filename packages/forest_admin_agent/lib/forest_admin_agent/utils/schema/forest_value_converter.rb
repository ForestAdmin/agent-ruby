require 'base64'

module ForestAdminAgent
  module Utils
    module Schema
      class ForestValueConverter
        #  This last form data parser tries to guess the types from the data itself.
        #
        #  - Fields with type "Collection" which target collections where the pk is not a string or
        #  derivative (mongoid, uuid, ...) won't be parser correctly, as we don't have enough information
        #  to properly guess the type
        #  - Fields of type "String" but where the final user entered a data-uri manually in the frontend
        #  will be wrongfully parsed.
        def self.make_form_data_unsafe(raw_data)
          data = {}
          raw_data.each do |key, value|
            # Skip fields from the default form
            next if Schema::GeneratorAction::DEFAULT_FIELDS.map { |f| f[:field] }.include?(key)

            data[key] = if value.is_a?(Array) && value.all? { |v| data_uri?(v) }
                          value.map { |uri| parse_data_uri(uri) }
                        elsif data_uri?(value)
                          parse_data_uri(value)
                        else
                          value
                        end
          end

          data
        end

        def self.make_form_data_from_fields(datasource, fields)
          data = {}

          fields.each do |field|
            next if Schema::GeneratorAction::DEFAULT_FIELDS.map { |f| f[:field] }.include?(field['field'])

            if field['reference'] && field['value']
              collection_name = field['reference'].split('.').first
              collection = datasource.get_collection(collection_name)
              data[field['field']] = Utils::Id.unpack_id(collection, field['value'])
            elsif field['type'] == 'File'
              data[field['field']] = parse_data_uri(field['value'])
            elsif field['type'].is_a?(Array) && field['type'][0] == 'File'
              data[field['field']] = field['value'].map { |v| parse_data_uri(v) }
            else
              data[field['field']] = field['value']
            end
          end

          data
        end

        # Proper form data parser which converts data from an action form result to the format
        # that is internally used in datasources.
        def self.make_form_data(datasource, raw_data, fields)
          data = {}
          raw_data.each do |key, value|
            field = fields.find { |f| f.label == key }
            # Skip fields from the default form
            next if Schema::GeneratorAction::DEFAULT_FIELDS.map { |f| f[:field] }.include?(key)

            if ActionFields.collection_field?(field) && !value.nil?
              collection = datasource.get_collection(field.collection_name)
              data[key] = Utils::Id.unpack_id(collection, value)
            elsif ActionFields.file_field?(field)
              data[key] = parse_data_uri(value)
            elsif ActionFields.file_list_field?(field)
              data[key] = value.map { |v| parse_data_uri(v) }
            else
              data[key] = value
            end
          end

          data
        end

        def self.data_uri?(value)
          value.is_a?(String) && value.start_with?('data:')
        end

        def self.value_to_forest(field)
          if ActionFields.enum_field?(field)
            return field.enum_values.include?(field.value) ? field.value : nil
          end

          return field.value.select { |v| field.enum_values.include?(v) } if ActionFields.enum_list_field?(field)

          return field.value&.join('|') if ActionFields.collection_field?(field)

          return make_data_uri(field.value) if ActionFields.file_field?(field)

          return value.map { |f| make_data_uri(f) } if ActionFields.file_list_field?(field)

          field.value
        end

        def self.make_data_uri(file)
          return if file.nil?

          mime_type = `file --b --mime-type #{file.path}`.strip
          value = Base64.strict_encode64(File.read(file.path))

          "data:#{mime_type};base64,#{value}"
        end

        def self.parse_data_uri(data_uri)
          return if data_uri.nil?

          header, data = data_uri[5, data_uri.size].split(',')
          mime_type, *media_types = header.split(';')
          result = { 'mime_type' => mime_type, 'buffer' => Base64.strict_decode64(data) }

          media_types.each do |media_type|
            if (index = media_type.index('='))
              result[media_type[0, index]] = CGI.unescape(media_type[index + 1, media_type.size])
            end
          end

          result
        end
      end
    end
  end
end
