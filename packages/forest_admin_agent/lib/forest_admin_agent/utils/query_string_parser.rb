require 'jwt'

module ForestAdminAgent
  module Utils
    class QueryStringParser
      include ForestAdminDatasourceToolkit::Exceptions
      include ForestAdminDatasourceToolkit::Components
      include ForestAdminDatasourceToolkit::Components::Query

      DEFAULT_ITEMS_PER_PAGE = 15.freeze
      DEFAULT_PAGE_TO_SKIP = 1.freeze

      def self.parse_caller(args)
        unless args[:headers]['HTTP_AUTHORIZATION']
          raise Exceptions::ForestException 'You must be logged in to access at this resource.'
        end

        timezone = args[:params]['timezone']
        raise Exceptions::ForestException 'You must be logged in to access at this resource.' unless timezone

        unless Time.find_zone(timezone)
          raise Exceptions::ForestException, "Invalid timezone: #{timezone}"
        end

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
        fields = args[:params][:fields][collection.name]

        return ProjectionFactory.all(collection) unless fields != '' && !fields.nil?

        fields = fields.split(',').map do |field_name|
          column = collection.fields[field_name]
          column.type == 'Column' ? field_name : field_name + ":" + args[:params][:fields][field_name]
        end

        Projection.new(fields)
      rescue
        # TODO: raise
      end

      def self.parse_projection_with_pks(collection, args)
        projection = self.parse_projection(collection, args)

        projection.with_pks(collection)
      end

      def self.parse_pagination(args)
        items_per_pages = args.dig(:params, :data, :attributes, :all_records_subset_query, :size) ||
          args.dig(:params, :page, :size) || DEFAULT_ITEMS_PER_PAGE

        page = args.dig(:params, :data, :attributes, :all_records_subset_query, :number) ||
          args.dig(:params, :page, :number) || DEFAULT_PAGE_TO_SKIP

        unless (!!(items_per_pages.match(/\A[-+]?\d+\z/)) || !!(page.match(/\A[-+]?\d+\z/)))
          raise ForestException "Invalid pagination [limit: #{items_per_pages}, skip: #{page}]"
        end

        offset = (page.to_i - 1) * items_per_pages.to_i

        Page.new(offset: offset, limit: items_per_pages)
      end
    end
  end
end
