module ForestAdminAgent
  module Routes
    class AbstractAuthenticatedRoute < AbstractRoute
      def build(args = {})
        if args.dig(:headers, 'action_dispatch.remote_ip')
          Facades::Whitelist.check_ip(args[:headers]['action_dispatch.remote_ip'].to_s)
        end
        @caller = Utils::QueryStringParser.parse_caller(args)
        @permissions = ForestAdminAgent::Services::Permissions.new(@caller)
        super
      end

      def format_attributes(args)
        record = args[:params][:data][:attributes] || {}

        args[:params][:data][:relationships]&.map do |field, value|
          schema = @collection.schema[:fields][field]

          record[schema.foreign_key] = value['data']['id'] if schema.type == 'ManyToOne'
        end

        record || {}
      end
    end
  end
end
