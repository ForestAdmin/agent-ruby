require 'jsonapi-serializers'

module ForestAdminAgent
  module Serializer
    class ForestSerializer
      include JSONAPI::Serializer

      attr_accessor :attributes_map
      attr_accessor :to_one_associations
      attr_accessor :to_many_associations

      JSONAPI::Serializer.send(:include, ForestSerializerOverride)

      def initialize(object, options = nil)
        super
      end

      def base_url
        '/forest'
      end

      def type
        class_name = @options[:class_name]
        @@class_names[class_name] ||= class_name.gsub('::', '__')
      end

      def id
        forest_collection = ForestAdminAgent::Facades::Container.datasource.get_collection(
          @options[:class_name].gsub('::', '__')
        )
        primary_keys = ForestAdminDatasourceToolkit::Utils::Schema.primary_keys(forest_collection)
        id = []
        primary_keys.each { |key| id << @object[key] }

        id.join('|')
      end

      def format_name(attribute_name)
        attribute_name.to_s
      end

      def add_attribute(name, options = {}, &block)
        @attributes_map ||= {}
        @attributes_map[name] = format_field(name, options)
      end

      def format_field(name, options)
        {
          attr_or_block: block_given? ? block : name,
          options: options,
        }
      end

      def attributes
        forest_collection = ForestAdminAgent::Facades::Container.datasource.get_collection(
          @options[:class_name].gsub('::', '__')
        )
        fields = forest_collection.schema[:fields].select { |_field_name, field| field.type == 'Column' }
        fields.each { |field_name, _field| add_attribute(field_name) }
        return {} if attributes_map.nil?
        attributes = {}

        attributes_map.each do |attribute_name, attr_data|
          next if !should_include_attr?(attribute_name, attr_data)
          value = evaluate_attr_or_block(attribute_name, attr_data[:attr_or_block])
          attributes[format_name(attribute_name)] = value
        end
        attributes
      end

      def evaluate_attr_or_block(attribute_name, attr_or_block)
        if attr_or_block.is_a?(Proc)
          # A custom block was given, call it to get the value.
          instance_eval(&attr_or_block)
        else
          # Default behavior, call a method by the name of the attribute.
          object[attr_or_block]
        end
      end

      def add_to_one_association(name, options = {}, &block)
        options[:include_links] = options.fetch(:include_links, true)
        options[:include_data] = options.fetch(:include_data, false)
        @to_one_associations ||= {}
        @to_one_associations[name] = format_field(name, options)
      end

      def has_one_relationships
        return {} if @to_one_associations.nil?
        data = {}
        @to_one_associations.each do |attribute_name, attr_data|
          next if !should_include_attr?(attribute_name, attr_data)
          data[attribute_name.to_sym] = attr_data
        end
        data
      end

      def has_many_relationships
        return {} if @to_many_associations.nil?
        data = {}
        @to_many_associations.each do |attribute_name, attr_data|
          next if !should_include_attr?(attribute_name, attr_data)
          data[attribute_name.to_sym] = attr_data
        end
        data
      end

      def add_to_many_association(name, options = {}, &block)
        options[:include_links] = options.fetch(:include_links, true)
        options[:include_data] = options.fetch(:include_data, false)
        @to_many_associations ||= {}
        @to_many_associations[name] = format_field(name, options)
      end

      def relationships
        datasource = ForestAdminAgent::Facades::Container.datasource
        forest_collection = datasource.get_collection(@options[:class_name].gsub('::', '__'))
        relations_to_many = forest_collection.schema[:fields].select do |_field_name, field|
          %w[OneToMany ManyToMany PolymorphicOneToMany].include?(field.type)
        end
        relations_to_one = forest_collection.schema[:fields].select do |_field_name, field|
          %w[OneToOne ManyToOne PolymorphicManyToOne PolymorphicOneToOne].include?(field.type)
        end

        relations_to_one.each { |field_name, _field| add_to_one_association(field_name) }

        data = {}
        has_one_relationships.each do |attribute_name, attr_data|
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
          if object.nil? || object.empty?
            data[formatted_attribute_name]['data'] = nil
          else
            relation = datasource.get_collection(@options[:class_name].gsub('::', '__'))
                                 .schema[:fields][attribute_name.to_s]
            options = @options.clone
            if relation.type == 'PolymorphicManyToOne'
              options[:class_name] = @object[relation.foreign_key_type_field]
              related_object_serializer = ForestSerializer.new(object, options)
              data[formatted_attribute_name]['data'] = {
                'type' => related_object_serializer.type.to_s,
                'id' => related_object_serializer.id.to_s,
              }
            else
              options[:class_name] = datasource.get_collection(relation.foreign_collection).name
              related_object_serializer = ForestSerializer.new(object, options)
              data[formatted_attribute_name]['data'] = {
                'type' => related_object_serializer.type.to_s,
                'id' => related_object_serializer.id.to_s,
              }
            end
          end
        end

        relations_to_many.each { |field_name, _field| add_to_many_association(field_name) }

        has_many_relationships.each do |attribute_name, attr_data|
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
            relation = datasource.get_collection(@options[:class_name].gsub('::', '__')).schema[:fields][attribute_name.to_s]
            options = @options.clone
            options[:class_name] = datasource.get_collection(relation.foreign_collection).name
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

      def relationship_self_link(attribute_name)
        "#{self_link}/relationships/#{format_name(attribute_name)}"
      end

      def relationship_related_link(attribute_name)
        "#{self_link}/#{format_name(attribute_name)}"
      end
    end
  end
end
