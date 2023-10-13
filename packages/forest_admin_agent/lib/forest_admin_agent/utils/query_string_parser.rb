require 'jwt'
require 'active_support/time'

module ForestAdminAgent
  module Utils
    class QueryStringParser
      include ForestAdminDatasourceToolkit::Exceptions
      include ForestAdminDatasourceToolkit::Components
      include ForestAdminDatasourceToolkit::Components::Query

      DEFAULT_ITEMS_PER_PAGE = '15'.freeze
      DEFAULT_PAGE_TO_SKIP = '1'.freeze

      def self.parse_caller(args)
        unless args.dig(:headers, 'HTTP_AUTHORIZATION')
          # TODO: replace by http exception
          raise ForestException, 'You must be logged in to access at this resource.'
        end

        timezone = args[:params]['timezone']
        raise ForestException, 'Missing timezone' unless timezone

        raise ForestException, "Invalid timezone: #{timezone}" unless Time.find_zone(timezone)

        token = args[:headers]['HTTP_AUTHORIZATION'].split[1]
        token_data = JWT.decode(
          token,
          Facades::Container.cache(:auth_secret),
          true,
          { algorithm: 'HS256' }
        )[0]
        token_data.delete('exp')
        token_data[:timezone] = timezone

        Caller.new(**token_data.transform_keys(&:to_sym))
      end

      def self.parse_projection(collection, args)
        fields = args.dig(:params, :fields, collection.name) || ''

        return ProjectionFactory.all(collection) unless fields != '' && !fields.nil?

        fields = fields.split(',').map do |field_name|
          column = collection.fields[field_name.strip]
          column.type == 'Column' ? field_name.strip : "#{field_name.strip}:#{args[:params][:fields][field_name.strip]}"
        end

        Projection.new(fields)
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
    end
  end
end
