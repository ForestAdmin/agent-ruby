module ForestAdminAgent
  module Utils
    class QueryStringParser
      include ForestAdminDatasourceToolkit::Exceptions
      include ForestAdminDatasourceToolkit::Components
      include ForestAdminDatasourceToolkit::Components::Query
      include ForestAdminDatasourceToolkit::Validations

      DEFAULT_ITEMS_PER_PAGE = '15'.freeze
      DEFAULT_PAGE_TO_SKIP = '1'.freeze

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

        fields = fields.split(',').map do |field_name|
          column = collection.schema[:fields][field_name.strip]
          if column.type == 'Column'
            field_name.strip
          elsif column.type == 'PolymorphicManyToOne'
            "#{field_name.strip}:*"
          else
            "#{field_name.strip}:#{args[:params][:fields][field_name.strip]}"
          end
        end

        projection = Projection.new(fields)
        ForestAdminDatasourceToolkit::Validations::ProjectionValidator.validate?(collection, projection)

        projection
      end

      def self.parse_projection_with_pks(collection, args)
        projection = parse_projection(collection, args)

        projection.with_pks(collection)
      end

      def self.parse_pagination(args)
        items_per_pages = args.dig(:params, :data, :attributes, :all_records_subset_query, :size) ||
                          args.dig(:params, :page, :size) || DEFAULT_ITEMS_PER_PAGE

        page = args.dig(:params, :data, :attributes, :all_records_subset_query, :number) ||
               args.dig(:params, :page, :number) || DEFAULT_PAGE_TO_SKIP

        unless !items_per_pages.to_s.match(/\A[+]?\d+\z/).nil? || !page.to_s.match(/\A[+]?\d+\z/).nil?
          raise ForestException, "Invalid pagination [limit: #{items_per_pages}, skip: #{page}]"
        end

        offset = (page.to_i - 1) * items_per_pages.to_i

        Page.new(offset: offset, limit: items_per_pages.to_i)
      end

      def self.parse_export_pagination(limit)
        page = DEFAULT_PAGE_TO_SKIP

        offset = (page.to_i - 1) * (limit ? limit.to_i : 0)

        Page.new(offset: offset, limit: limit&.to_i)
      end

      def self.parse_search(collection, args)
        search = args.dig(:params, :data, :attributes, :all_records_subset_query, :search) || args.dig(:params, :search)

        raise ForestException, 'Collection is not searchable' if search && !collection.is_searchable?

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

      def self.parse_segment(collection, args)
        segment = args.dig(:params, :data, :attributes, :all_records_subset_query,
                           :segment) || args.dig(:params, :segment)

        return unless segment

        raise ForestException, "Invalid segment: #{segment}" unless collection.schema[:segments].include?(segment)

        segment
      end
    end
  end
end
