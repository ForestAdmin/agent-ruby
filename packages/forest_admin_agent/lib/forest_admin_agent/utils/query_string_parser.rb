module ForestAdminAgent
  module Utils
    class QueryStringParser
      include ForestAdminAgent::Http::Exceptions
      include ForestAdminDatasourceToolkit::Exceptions
      include ForestAdminDatasourceToolkit::Components
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminDatasourceToolkit::Validations

      DEFAULT_ITEMS_PER_PAGE = '15'.freeze
      DEFAULT_PAGE_TO_SKIP = '1'.freeze
      POLYMORPHIC_TARGET_WILDCARD = '*'.freeze

      def self.parse_condition_tree(collection, args)
        filters = begin
          args.dig(:params, :data, :attributes, :all_records_subset_query, :filters) ||
            args.dig(:params, :filters) || args.dig(:params, :filter)
        rescue StandardError
          nil
        end

        return if filters.nil?

        filters = JSON.parse(filters, symbolize_names: true) if filters.is_a? String
        condition_tree = ConditionTreeParser.from_plain_object(collection, filters)
        ConditionTreeValidator.validate(condition_tree, collection)

        condition_tree
      end

      def self.parse_caller(args)
        CallerParser.new(args).parse
      end

      def self.parse_projection(collection, args)
        fields = args.dig(:params, :fields, collection.name) || ''

        return ProjectionFactory.all(collection) unless fields != '' && !fields.nil?

        requested_field_names = fields.split(',').map(&:strip)
        add_polymorphic_type_fields(collection, requested_field_names)
        projection_fields = build_projection_fields(collection, requested_field_names, args)

        ForestAdminDatasourceToolkit::Validations::ProjectionValidator.validate?(collection, projection_fields)

        Projection.new(projection_fields)
      rescue ForestAdminDatasourceToolkit::Exceptions::ForestException => e
        raise BadRequestError, "Invalid projection: #{e.message}"
      end

      def self.parse_projection_from_header(collection, args)
        header = args.dig(:headers, 'HTTP_FOREST_PROJECTION')&.to_s&.strip

        return if header.nil? || header.empty?

        projection_fields = build_header_projection_fields(collection, header.split(',', -1).map(&:strip))

        ForestAdminDatasourceToolkit::Validations::ProjectionValidator.validate?(collection, projection_fields)

        Projection.new(projection_fields)
      rescue ForestAdminDatasourceToolkit::Exceptions::ForestException => e
        raise BadRequestError, "Invalid Forest-Projection header: #{e.message}"
      end

      def self.parse_projection_from_request(collection, args)
        parse_projection_from_header(collection, args) || parse_projection(collection, args)
      end

      # The projection, and whether the caller named the fields in it. Both halves read the same
      # `fields` param the same way on purpose: an empty `fields[<collection>]=` means "every
      # column", so it is not named and must take the redaction path rather than a 403.
      def self.parse_requested_projection(collection, args)
        from_header = parse_projection_from_header(collection, args)

        return { projection: from_header, named_by_caller: true } if from_header

        fields = args.dig(:params, :fields, collection.name)

        {
          projection: parse_projection(collection, args),
          named_by_caller: !(fields.nil? || fields == '')
        }
      end

      def self.add_polymorphic_type_fields(collection, requested_field_names)
        polymorphic_relations = collection.schema[:fields].select { |_, field| field.type == 'PolymorphicManyToOne' }

        polymorphic_relations.each do |relation_name, relation_field|
          foreign_key = relation_field.foreign_key
          type_field = relation_field.foreign_key_type_field

          relation_requested = requested_field_names.include?(relation_name)
          foreign_key_requested = requested_field_names.include?(foreign_key)
          type_field_missing = !requested_field_names.include?(type_field)

          requested_field_names << type_field if (relation_requested || foreign_key_requested) && type_field_missing
        end
      end

      def self.build_projection_fields(collection, requested_field_names, args)
        requested_field_names.flat_map do |field_name|
          field = get_field(collection, field_name)

          case field.type
          when 'Column'
            field_name
          when 'PolymorphicManyToOne'
            "#{field_name}:#{POLYMORPHIC_TARGET_WILDCARD}"
          else
            relation_fields = args.dig(:params, :fields, field_name)

            if relation_fields.nil? || relation_fields.empty?
              "#{field_name}:#{relation_fields}"
            else
              relation_fields.split(',').map { |sub_field| "#{field_name}:#{sub_field.strip}" }
            end
          end
        end
      end

      def self.build_header_projection_fields(collection, requested_paths)
        if requested_paths.any? { |path| path.empty? || path.split(':', -1).any?(&:empty?) }
          raise ForestAdminDatasourceToolkit::Exceptions::ValidationError, 'The projection contains an empty field.'
        end

        root_field_names = requested_paths.map { |path| path.split(':').first }
        root_field_names_with_types = root_field_names.dup
        add_polymorphic_type_fields(collection, root_field_names_with_types)

        projection_fields = requested_paths.map { |path| expand_polymorphic_leaf(collection, path) }

        projection_fields |
          (root_field_names_with_types - root_field_names) |
          nested_polymorphic_linkage_fields(collection, projection_fields)
      end

      def self.expand_polymorphic_leaf(collection, path)
        segments = path.split(':')
        leaf_index = segments.size - 1

        each_field_along_path(collection, segments) do |field, index|
          return "#{path}:#{POLYMORPHIC_TARGET_WILDCARD}" if polymorphic_many_to_one?(field) && index == leaf_index
        end

        path
      end

      def self.nested_polymorphic_linkage_fields(collection, projection_fields)
        projection_fields.flat_map do |path|
          segments = path.split(':')

          each_field_along_path(collection, segments).flat_map do |field, index|
            next [] unless polymorphic_many_to_one?(field) && index.positive?

            polymorphic_linkage_columns(field, segments[0...index])
          end
        end
      end

      def self.polymorphic_linkage_columns(field, relation_path)
        [field.foreign_key_type_field, field.foreign_key].map { |column| (relation_path + [column]).join(':') }
      end

      def self.each_field_along_path(collection, segments)
        return to_enum(:each_field_along_path, collection, segments) unless block_given?

        current_collection = collection

        segments.each_with_index do |segment, index|
          field = field_along_path(current_collection, segment, root: index.zero?)
          break if field.nil?

          yield field, index

          break unless field.respond_to?(:foreign_collection)

          current_collection = collection.datasource.get_collection(field.foreign_collection)
        end
      end

      def self.field_along_path(collection, segment, root:)
        root ? get_field(collection, segment) : collection.schema[:fields][segment]
      end

      def self.polymorphic_many_to_one?(field)
        field.type == 'PolymorphicManyToOne'
      end

      def self.get_field(collection, field_name)
        field = collection.schema[:fields][field_name]
        return field unless field.nil?

        available_fields = collection.schema[:fields].keys.join(', ')
        raise ForestAdminDatasourceToolkit::Exceptions::ValidationError,
              "The '#{collection.name}.#{field_name}' field was not found. " \
              "Available fields are: [#{available_fields}]. " \
              'Please check if the field name is correct.'
      end
      private_class_method :add_polymorphic_type_fields, :build_projection_fields,
                           :build_header_projection_fields, :get_field,
                           :expand_polymorphic_leaf, :nested_polymorphic_linkage_fields,
                           :polymorphic_linkage_columns, :each_field_along_path,
                           :field_along_path, :polymorphic_many_to_one?

      def self.parse_projection_with_pks(collection, args)
        parse_projection_from_request(collection, args).with_pks(collection)
      end

      def self.parse_pagination(args)
        items_per_pages = args.dig(:params, :data, :attributes, :all_records_subset_query, :size) ||
                          args.dig(:params, :page, :size) || DEFAULT_ITEMS_PER_PAGE

        page = args.dig(:params, :data, :attributes, :all_records_subset_query, :number) ||
               args.dig(:params, :page, :number) || DEFAULT_PAGE_TO_SKIP

        # Validate both parameters
        page_valid = !page.to_s.match(/\A[+]?\d+\z/).nil? && page.to_i.positive?
        limit_valid = !items_per_pages.to_s.match(/\A[+]?\d+\z/).nil? && items_per_pages.to_i.positive?

        unless page_valid && limit_valid
          raise BadRequestError, "Invalid pagination [limit: #{items_per_pages}, skip: #{page}]"
        end

        offset = (page.to_i - 1) * items_per_pages.to_i

        Page.new(offset: offset, limit: items_per_pages.to_i)
      end

      def self.parse_export_pagination(limit)
        Page.new(offset: 0, limit: limit&.to_i)
      end

      def self.parse_search(collection, args)
        search = args.dig(:params, :data, :attributes, :all_records_subset_query, :search) || args.dig(:params, :search)

        raise BadRequestError, 'Collection is not searchable' if search && !collection.is_searchable?

        search
      end

      def self.parse_search_extended(args)
        extended = args.dig(:params, :data, :attributes, :all_records_subset_query,
                            :searchExtended) || args.dig(:params, :searchExtended)

        return false if extended.nil?

        extended != '0'
      end

      def self.parse_sort(collection, args)
        raw_sort_string = args.dig(:params, :sort)

        return SortUtils::SortFactory.by_primary_keys(collection) unless raw_sort_string

        sort_list = []
        raw_sort_string.split(',').map do |sort_string|
          field = sort_string.tr('.', ':')
          ascending = !sort_string.start_with?('-')
          field = field[1..] unless ascending

          sort_list.push({ field: field, ascending: ascending })
        end

        sort = Sort.new(sort_list)

        ForestAdminDatasourceToolkit::Validations::SortValidator.validate(collection, sort)

        sort
      end

      def self.parse_chart_parameters(args)
        params = args[:params] || {}

        params.each_with_object({}) do |(key, value), result|
          key_s = key.to_s
          next if value.nil? || value.is_a?(Hash) || value.is_a?(Array)

          result[key_s] = value.to_s
        end
      end

      def self.parse_segment(collection, args)
        segment = args.dig(:params, :data, :attributes, :all_records_subset_query,
                           :segment) || args.dig(:params, :segment)

        return unless segment

        raise BadRequestError, "Invalid segment: #{segment}" unless collection.schema[:segments].include?(segment)

        segment
      end
    end
  end
end
