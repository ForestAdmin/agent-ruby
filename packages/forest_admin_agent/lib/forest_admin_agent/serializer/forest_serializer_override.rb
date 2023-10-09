module ForestAdminAgent
  module Serializer
    module ForestSerializerOverride
      def self.included base
        base.instance_eval do
          def self.find_serializer_class_name(object, options)
            if options[:serializer]
              return options[:serializer].to_s
            end
            if options[:namespace]
              return "#{options[:namespace]}::#{object.class.name}Serializer"
            end
            if object.respond_to?(:jsonapi_serializer_class_name)
              return object.jsonapi_serializer_class_name.to_s
            end
            "#{object.class.name}Serializer"
          end


          def self.find_recursive_relationships(root_object, root_inclusion_tree, results, options)
            root_inclusion_tree.each do |attribute_name, child_inclusion_tree|
              # Skip the sentinal value, but we need to preserve it for siblings.
              next if attribute_name == :_include

              serializer = JSONAPI::Serializer.find_serializer(root_object, options)
              serializer.relationships
              unformatted_attr_name = serializer.unformat_name(attribute_name).to_sym

              # We know the name of this relationship, but we don't know where it is stored internally.
              # Check if it is a has_one or has_many relationship.
              object = nil
              is_collection = false
              is_valid_attr = false
              if serializer.has_one_relationships.has_key?(unformatted_attr_name)
                is_valid_attr = true
                attr_data = serializer.has_one_relationships[unformatted_attr_name]
                object = serializer.has_one_relationship(unformatted_attr_name, attr_data)
              elsif serializer.has_many_relationships.has_key?(unformatted_attr_name)
                is_valid_attr = true
                is_collection = true
                attr_data = serializer.has_many_relationships[unformatted_attr_name]
                object = serializer.has_many_relationship(unformatted_attr_name, attr_data)
              end

              if !is_valid_attr
                raise JSONAPI::Serializer::InvalidIncludeError.new(
                  "'#{attribute_name}' is not a valid include.")
              end

              if attribute_name != serializer.format_name(attribute_name)
                expected_name = serializer.format_name(attribute_name)

                raise JSONAPI::Serializer::InvalidIncludeError.new(
                  "'#{attribute_name}' is not a valid include.  Did you mean '#{expected_name}' ?"
                )
              end

              # We're finding relationships for compound documents, so skip anything that doesn't exist.
              next if object.nil?

              # Full linkage: a request for comments.author MUST automatically include comments
              # in the response.
              objects = is_collection ? object : [object]
              if child_inclusion_tree[:_include] == true
                # Include the current level objects if the _include attribute exists.
                # If it is not set, that indicates that this is an inner path and not a leaf and will
                # be followed by the recursion below.
                objects.each do |obj|
                  obj_serializer = JSONAPI::Serializer.find_serializer(obj, options)
                  # Use keys of ['posts', '1'] for the results to enforce uniqueness.
                  # Spec: A compound document MUST NOT include more than one resource object for each
                  # type and id pair.
                  # http://jsonapi.org/format/#document-structure-compound-documents
                  key = [obj_serializer.type, obj_serializer.id]

                  # This is special: we know at this level if a child of this parent will also been
                  # included in the compound document, so we can compute exactly what linkages should
                  # be included by the object at this level. This satisfies this part of the spec:
                  #
                  # Spec: Resource linkage in a compound document allows a client to link together
                  # all of the included resource objects without having to GET any relationship URLs.
                  # http://jsonapi.org/format/#document-structure-resource-relationships
                  current_child_includes = []
                  inclusion_names = child_inclusion_tree.keys.reject { |k| k == :_include }
                  inclusion_names.each do |inclusion_name|
                    if child_inclusion_tree[inclusion_name][:_include]
                      current_child_includes << inclusion_name
                    end
                  end

                  # Special merge: we might see this object multiple times in the course of recursion,
                  # so merge the include_linkages each time we see it to load all the relevant linkages.
                  current_child_includes += results[key] && results[key][:include_linkages] || []
                  current_child_includes.uniq!
                  results[key] = {object: obj, include_linkages: current_child_includes}
                end
              end

              # Recurse deeper!
              if !child_inclusion_tree.empty?
                # For each object we just loaded, find all deeper recursive relationships.
                objects.each do |obj|
                  find_recursive_relationships(obj, child_inclusion_tree, results, options)
                end
              end
            end
            nil
          end

        end
      end
    end
  end
end
