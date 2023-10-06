require 'jsonapi-serializers'

module ForestAdminAgent
  module Serializer
    class ForestSerializer
      include JSONAPI::Serializer

      attr_accessor :attributes_map
      attr_accessor :to_one_associations
      attr_accessor :to_many_associations

      def base_url
        ForestAdminRails.config[:prefix]
      end

      def type
        class_name = object.class.name
        @@class_names[class_name] ||= class_name.demodulize.underscore.freeze
      end

      def format_name(attribute_name)
        attribute_name.to_s
      end

      def add_attribute(name, options = {}, &block)
        @attributes_map ||= {}
        @attributes_map[name] = format_field(name, options)
      end

      def attributes
        # forest_collection = ForestAdminAgent::Facades::Container.datasource.collection(object.class.name.demodulize.underscore)
        # fields = forest_collection.getFields.reject { |field| field.is_a?(ForestAdminDatasourceToolkit::Schema::Relations::RelationSchema) }
        fields = [:first_name, :last_name]
        fields.each { |field| add_attribute(field.name) }

        return {} if attributes_map.nil?
        attributes = {}
        attributes_map.each do |attribute_name, attr_data|
          next if !should_include_attr?(attribute_name, attr_data)
          value = evaluate_attr_or_block(attribute_name, attr_data[:attr_or_block])
          attributes[format_name(attribute_name)] = value
        end
        attributes
      end

      def add_to_one_association(name, options = {}, &block)
        options[:include_links] = options.fetch(:include_links, true)
        options[:include_data] = options.fetch(:include_data, false)
        @to_one_associations ||= {}
        @to_one_associations[name] = format_field(name, options)
      end

      def add_to_many_association(name, options = {}, &block)
        options[:include_links] = options.fetch(:include_links, true)
        options[:include_data] = options.fetch(:include_data, false)
        @to_many_associations ||= {}
        @to_many_associations[name] = format_field(name, options)
      end

      def has_relationships(type)
        return {} if send("to_#{type}_associations").nil?
        data = {}
        send("to_#{type}_associations").each do |attribute_name, attr_data|
          next if !should_include_attr?(attribute_name, attr_data)
          data[attribute_name] = attr_data
        end
        data
      end

      def format_field(name, options)
        {
          attr_or_block: block_given? ? block : name,
          options: options,
        }
      end

      def relationships
        # forest_collection = ForestAdminAgent::Facades::Container.datasource.collection(object.class.name.demodulize.underscore)
        # relations_many_to_one = forest_collection.getFields.select { |field| field.is_a?(ForestAdminDatasourceToolkit::Schema::Relations::ManyToOneSchema) }
        # relations_one_to_one = forest_collection.getFields.select { |field| field.is_a?(ForestAdminDatasourceToolkit::Schema::Relations::OneToOneSchema) }

        # TO REMOVE
        relations_one_to_one = []
        relations_one_to_one.each { |name| add_to_one_association(name) }

        data = {}
        has_relationships('one').each do |attribute_name, attr_data|
          formatted_attribute_name = format_name(attribute_name)
          data[formatted_attribute_name] = {}

          if attr_data[:options][:include_links]
            links_self = relationship_self_link(attribute_name)
            links_related = relationship_related_link(attribute_name)
            data[formatted_attribute_name]['links'] = {} if links_self || links_related
            data[formatted_attribute_name]['links']['related'] = {} if links_self
            data[formatted_attribute_name]['links']['related']['href'] = links_self if links_self
          end

          object = has_one_relationship(attribute_name, attr_data)
          if object.nil?
            data[formatted_attribute_name]['data'] = nil
          else
            related_object_serializer = ForestSerializer.new(object, @options)
            data[formatted_attribute_name]['data'] = {
              'type' => related_object_serializer.type.to_s,
              'id' => related_object_serializer.id.to_s,
            }
          end
        end

        # TO REMOVE
        relations_many_to_one = []
        relations_many_to_one.each { |name| add_to_many_association(name) }

        has_relationships('many').each do |attribute_name, attr_data|
          formatted_attribute_name = format_name(attribute_name)

          data[formatted_attribute_name] = {}

          if attr_data[:options][:include_links]
            links_self = relationship_self_link(attribute_name)
            links_related = relationship_related_link(attribute_name)
            data[formatted_attribute_name]['links'] = {} if links_self || links_related
            data[formatted_attribute_name]['links']['related'] = {} if links_self
            data[formatted_attribute_name]['links']['related']['href'] = links_self if links_self
          end

          if @_include_linkages.include?(formatted_attribute_name) || attr_data[:options][:include_data]
            data[formatted_attribute_name]['data'] = []
            objects = has_many_relationship(attribute_name, attr_data) || []
            objects.each do |obj|
              related_object_serializer = JSONAPI::Serializer.find_serializer(obj, @options)
              data[formatted_attribute_name]['data'] << {
                'type' => related_object_serializer.type.to_s,
                'id' => related_object_serializer.id.to_s,
              }
            end
          end
        end
        data
      end
    end
  end
end
