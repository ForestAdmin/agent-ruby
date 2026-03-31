require 'base64'
require 'cgi'
require 'rack/mime'

module ForestAdminRails
  module Plugins
    class ActiveStorage < ForestAdminDatasourceCustomizer::Plugins::Plugin
      ACTIVE_STORAGE_COLLECTIONS = %w[
        ActiveStorage__Attachment
        ActiveStorage__Blob
        ActiveStorage__VariantRecord
      ].freeze

      def run(datasource_customizer, _collection_customizer = nil, options = {})
        datasource_customizer.collections.each do |name, collection|
          next if options[:only] && !options[:only].include?(name)
          next if options[:except]&.include?(name)

          add_attachment_fields(collection, options)
        end

        remove_active_storage_collections(datasource_customizer) if options.fetch(:hide_internal_collections, true)
      end

      private

      def remove_active_storage_collections(datasource_customizer)
        ACTIVE_STORAGE_COLLECTIONS.each do |collection_name|
          next unless datasource_customizer.collections.key?(collection_name)

          datasource_customizer.remove_collection(collection_name)
        end
      end

      def add_attachment_fields(collection, options)
        model_class = find_model_class(collection)
        return unless model_class
        return unless defined?(::ActiveStorage) && model_class.respond_to?(:reflect_on_all_attachments)

        model_class.reflect_on_all_attachments
                   .select { |a| a.macro == :has_one_attached }
                   .each do |attachment|
          name = attachment.name.to_s
          hide_attachment_relations(collection, name)
          add_file_field(collection, model_class, name, options.fetch(:download_images_on_list, false))
        end
      end

      def hide_attachment_relations(collection, attachment_name)
        %W[#{attachment_name}_attachment #{attachment_name}_blob].each do |relation_name|
          next unless collection.schema[:fields].key?(relation_name)

          collection.remove_field(relation_name)
        end
      end

      def add_file_field(collection, model_class, attachment_name, download_images_on_list)
        return if collection.schema[:fields][attachment_name]

        collection.add_field(attachment_name,
                             ForestAdminDatasourceCustomizer::Decorators::Computed::ComputedDefinition.new(
                               column_type: 'File',
                               dependencies: ['id'],
                               values: lambda { |records, _ctx|
                                 compute_values(records, model_class, attachment_name, download_images_on_list)
                               }
                             ))

        collection.replace_field_writing(attachment_name) do |value, context|
          handle_write(value, context, model_class, attachment_name)
        end
      end

      def compute_values(records, model_class, attachment_name, download_images_on_list)
        ids = records.map { |r| r['id'] }
        models = model_class
                 .where(id: ids)
                 .includes(:"#{attachment_name}_attachment", :"#{attachment_name}_blob")
                 .index_by(&:id)

        records.map do |record|
          model = models[record['id']]
          next nil unless model&.public_send(attachment_name)&.attached?

          blob = model.public_send(attachment_name).blob

          if records.length == 1 || (download_images_on_list && blob.content_type&.start_with?('image/'))
            content = blob.download
            "data:#{blob.content_type};name=#{CGI.escape(blob.filename.to_s)};base64,#{Base64.strict_encode64(content)}"
          else
            "data:#{blob.content_type};name=#{CGI.escape(blob.filename.to_s)};base64,"
          end
        end
      end

      def handle_write(value, context, model_class, attachment_name)
        record_id = context.filter&.condition_tree&.value
        return {} unless record_id

        record = model_class.find(record_id)

        if value.nil? || value.to_s.strip.empty?
          record.public_send(attachment_name).purge if record.public_send(attachment_name).attached?
        else
          parsed = ForestAdminAgent::Utils::Schema::ForestValueConverter.parse_data_uri(value)
          if parsed
            fallback_extension = Rack::Mime::MIME_TYPES.invert[parsed['mime_type']] || '.bin'
            record.public_send(attachment_name).attach(
              io: StringIO.new(parsed['buffer']),
              filename: parsed['name'] || "#{attachment_name}#{fallback_extension}",
              content_type: parsed['mime_type']
            )
          end
        end
        {}
      end

      def find_model_class(collection)
        current = collection.respond_to?(:collection) ? collection.collection : collection
        loop do
          return current.model if current.respond_to?(:model) && current.model.is_a?(Class)
          break unless current.respond_to?(:child_collection)

          current = current.child_collection
        end
        nil
      end
    end
  end
end
