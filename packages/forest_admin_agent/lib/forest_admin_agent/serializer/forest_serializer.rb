require 'jsonapi-serializers'

module ForestAdminAgent
  module Serializer
    class ForestSerializer
      include JSONAPI::Serializer

      TO_ONE_TYPES = %w[OneToOne ManyToOne PolymorphicManyToOne PolymorphicOneToOne].freeze
      TO_MANY_TYPES = %w[OneToMany ManyToMany PolymorphicOneToMany].freeze

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

      def self.reset_cache!
        @@primary_keys = {}
        @@layouts = {}.compare_by_identity
      end

      # Keyed by the collection object, not its name: two datasources can expose a collection under
      # the same name, and the decorator stack returns the same object for a name once built.
      def self.layout_for(collection)
        @@layouts ||= {}.compare_by_identity
        @@layouts[collection] ||= build_layout(collection)
      end

      def self.build_layout(collection)
        fields = collection.schema[:fields]
        relation = lambda do |types|
          fields.each_with_object({}) do |(name, field), layout|
            next unless types.include?(field.type)

            layout[name] = { attr_or_block: name, options: { include_links: true, include_data: false }.freeze }.freeze
          end.freeze
        end

        {
          fields: fields,
          attributes: fields.each_with_object({}) do |(name, field), layout|
            layout[name] = { attr_or_block: name, options: {}.freeze }.freeze if field.type == 'Column'
          end.freeze,
          to_one: relation.call(TO_ONE_TYPES),
          to_many: relation.call(TO_MANY_TYPES)
        }.freeze
      end

      def layout
        @layout ||= self.class.layout_for(ForestAdminAgent::Facades::Container.datasource.get_collection(type))
      end

      def attributes_map
        layout[:attributes]
      end

      def to_one_associations
        layout[:to_one]
      end

      def to_many_associations
        layout[:to_many]
      end

      def id
        @@primary_keys ||= {}
        primary_keys = @@primary_keys[type] ||= ForestAdminDatasourceToolkit::Utils::Schema.primary_keys(
          ForestAdminAgent::Facades::Container.datasource.get_collection(type)
        )
        primary_keys.map { |key| @object[key] }.join('|')
      end

      def format_name(attribute_name)
        attribute_name.to_s
      end

      def attributes
        attributes = {}

        attributes_map.each do |attribute_name, attr_data|
          next if !should_include_attr?(attribute_name, attr_data)
          value = evaluate_attr_or_block(attribute_name, attr_data[:attr_or_block])
          # Only include the attribute if it's not nil or if the key exists in the object
          # This prevents setting all fields to null for included records
          if value.nil?
            # Check if the key actually exists in the object (for Hash objects)
            # If the key exists in the object, it means that the value is purposely set to null
            next unless @object.is_a?(Hash) && @object.key?(attribute_name.to_s)
          end
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

      # A PolymorphicManyToOne can't be SQL-joined, so list projections return a phantom object with no
      # primary key. Rebuild the id from the foreign key on the owner record.
      def has_one_relationship(attribute_name, attr_data)
        object = super
        return object if object.nil? # relation not projected (e.g. update/store responses)

        field = layout[:fields][attribute_name.to_s]
        return object unless field&.type == 'PolymorphicManyToOne'

        foreign_key = @object[field.foreign_key]
        foreign_type = @object[field.foreign_key_type_field]
        return nil if foreign_key.nil? || foreign_type.nil?

        # foreign_key_targets is keyed by formatted collection names (Admin::User => Admin__User),
        # but foreign_type is the raw AR type column value, so format it before the lookup.
        primary_key = (field.foreign_key_targets || {})[foreign_type.gsub('::', '__')] || 'id'
        (object.is_a?(Hash) ? object : {}).merge(primary_key => foreign_key)
      end

      def has_one_relationships
        data = {}
        to_one_associations.each do |attribute_name, attr_data|
          next if !should_include_attr?(attribute_name, attr_data)
          data[attribute_name.to_sym] = attr_data
        end
        data
      end

      def has_many_relationships
        data = {}
        to_many_associations.each do |attribute_name, attr_data|
          next if !should_include_attr?(attribute_name, attr_data)
          data[attribute_name.to_sym] = attr_data
        end
        data
      end

      def relationships
        datasource = ForestAdminAgent::Facades::Container.datasource
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
          # Only include 'data' key if the relationship object exists
          # Omit 'data' key entirely when null instead of setting it to null
          unless object.nil? || (object.respond_to?(:empty?) && object.empty?)
            relation = layout[:fields][attribute_name.to_s]
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
            relation = layout[:fields][attribute_name.to_s]
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
