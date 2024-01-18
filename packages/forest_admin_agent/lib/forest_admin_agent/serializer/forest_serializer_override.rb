module ForestAdminAgent
  module Serializer
    module ForestSerializerOverride
      def self.included(base)
        base.instance_eval do
          def self.find_serializer_class_name(object, options)
            return options[:serializer].to_s if options[:serializer]
            return "#{options[:namespace]}::#{object.class.name}Serializer" if options[:namespace]
            return object.jsonapi_serializer_class_name.to_s if object.respond_to?(:jsonapi_serializer_class_name)

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
              if serializer.has_one_relationships.key?(unformatted_attr_name)
                is_valid_attr = true
                attr_data = serializer.has_one_relationships[unformatted_attr_name]
                object = serializer.has_one_relationship(unformatted_attr_name, attr_data)
              elsif serializer.has_many_relationships.key?(unformatted_attr_name)
                is_valid_attr = true
                is_collection = true
                attr_data = serializer.has_many_relationships[unformatted_attr_name]
                object = serializer.has_many_relationship(unformatted_attr_name, attr_data)
              end

              unless is_valid_attr
                raise JSONAPI::Serializer::InvalidIncludeError, "'#{attribute_name}' is not a valid include."
              end

              if attribute_name != serializer.format_name(attribute_name)
                expected_name = serializer.format_name(attribute_name)

                raise JSONAPI::Serializer::InvalidIncludeError,
                      "'#{attribute_name}' is not a valid include.  Did you mean '#{expected_name}' ?"
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
                    current_child_includes << inclusion_name if child_inclusion_tree[inclusion_name][:_include]
                  end

                  # Special merge: we might see this object multiple times in the course of recursion,
                  # so merge the include_linkages each time we see it to load all the relevant linkages.
                  current_child_includes += (results[key] && results[key][:include_linkages]) || []
                  current_child_includes.uniq!
                  results[key] = { object: obj, include_linkages: current_child_includes }
                end
              end

              # Recurse deeper!
              next if child_inclusion_tree.empty?

              # For each object we just loaded, find all deeper recursive relationships.
              objects.each do |obj|
                find_recursive_relationships(obj, child_inclusion_tree, results, options)
              end
            end
            nil
          end

          def self.serialize(objects, options = {})
            # Normalize option strings to symbols.
            options[:is_collection] = options.delete('is_collection') || options[:is_collection] || false
            options[:include] = options.delete('include') || options[:include]
            options[:serializer] = options.delete('serializer') || options[:serializer]
            options[:namespace] = options.delete('namespace') || options[:namespace]
            options[:context] = options.delete('context') || options[:context] || {}
            options[:skip_collection_check] = options.delete('skip_collection_check') || options[:skip_collection_check] || false
            options[:base_url] = options.delete('base_url') || options[:base_url]
            options[:jsonapi] = options.delete('jsonapi') || options[:jsonapi]
            options[:meta] = options.delete('meta') || options[:meta]
            options[:links] = options.delete('links') || options[:links]
            options[:fields] = options.delete('fields') || options[:fields] || {}

            # Deprecated: use serialize_errors method instead
            options[:errors] = options.delete('errors') || options[:errors]

            # Normalize includes.
            includes = options[:include]
            includes = (includes.is_a?(String) ? includes.split(',') : includes).uniq if includes

            # Transforms input so that the comma-separated fields are separate symbols in array
            # and keys are stringified
            # Example:
            # {posts: 'title,author,long_comments'} => {'posts' => [:title, :author, :long_comments]}
            # {posts: ['title', 'author', 'long_comments'} => {'posts' => [:title, :author, :long_comments]}
            #
            fields = {}
            # Normalize fields to accept a comma-separated string or an array of strings.
            options[:fields].map do |type, whitelisted_fields|
              whitelisted_fields = [whitelisted_fields] if whitelisted_fields.is_a?(Symbol)
              whitelisted_fields = whitelisted_fields.split(',') if whitelisted_fields.is_a?(String)
              fields[type.to_s] = whitelisted_fields.map(&:to_sym)
            end

            # An internal-only structure that is passed through serializers as they are created.
            passthrough_options = {
              context: options[:context],
              serializer: options[:serializer],
              namespace: options[:namespace],
              include: includes,
              fields: fields,
              base_url: options[:base_url],
              class_name: options[:class_name]
            }

            if !options[:skip_collection_check] && options[:is_collection] && !objects.respond_to?(:each)
              raise JSONAPI::Serializer::AmbiguousCollectionError.new(
                'Attempted to serialize a single object as a collection.')
            end

            # Automatically include linkage data for any relation that is also included.
            if includes
              include_linkages = includes.map { |key| key.to_s.split('.').first }
              passthrough_options[:include_linkages] = include_linkages
            end

            # Spec: Primary data MUST be either:
            # - a single resource object or null, for requests that target single resources.
            # - an array of resource objects or an empty array ([]), for resource collections.
            # http://jsonapi.org/format/#document-structure-top-level
            if options[:is_collection] && !objects.any?
              primary_data = []
            elsif !options[:is_collection] && objects.nil?
              primary_data = nil
            elsif options[:is_collection]
              # Have object collection.
              primary_data = serialize_primary_multi(objects, passthrough_options)
            else
              # Duck-typing check for a collection being passed without is_collection true.
              # We always must be told if serializing a collection because the JSON:API spec distinguishes
              # how to serialize null single resources vs. empty collections.
              if !options[:skip_collection_check] && objects.respond_to?(:each)
                raise JSONAPI::Serializer::AmbiguousCollectionError.new(
                  'Must provide `is_collection: true` to `serialize` when serializing collections.')
              end
              # Have single object.
              primary_data = serialize_primary(objects, passthrough_options)
            end
            result = {
              'data' => primary_data,
            }
            result['jsonapi'] = options[:jsonapi] if options[:jsonapi]
            result['meta'] = options[:meta] if options[:meta]
            result['links'] = options[:links] if options[:links]
            result['errors'] = options[:errors] if options[:errors]

            # If 'include' relationships are given, recursively find and include each object.
            if includes
              relationship_data = {}
              inclusion_tree = parse_relationship_paths(includes)

              # Given all the primary objects (either the single root object or collection of objects),
              # recursively search and find related associations that were specified as includes.
              objects = options[:is_collection] ? objects.to_a : [objects]
              objects.compact.each do |obj|
                # Use the mutability of relationship_data as the return datastructure to take advantage
                # of the internal special merging logic.
                find_recursive_relationships(obj, inclusion_tree, relationship_data, passthrough_options)
              end

              result['included'] = relationship_data.map do |_, data|
                included_passthrough_options = {}
                included_passthrough_options[:base_url] = passthrough_options[:base_url]
                included_passthrough_options[:context] = passthrough_options[:context]
                included_passthrough_options[:fields] = passthrough_options[:fields]
                included_passthrough_options[:serializer] = find_serializer_class(data[:object], options)
                included_passthrough_options[:namespace] = passthrough_options[:namespace]
                included_passthrough_options[:include_linkages] = data[:include_linkages]
                serialize_primary(data[:object], included_passthrough_options)
              end
            end
            result
          end
        end
      end
    end
  end
end
