module ForestAdminAgent
  module Routes
    class AbstractAuthenticatedRoute < AbstractRoute
      def build(args = {})
        if args.dig(:headers, 'action_dispatch.remote_ip')
          Facades::Whitelist.check_ip(args[:headers]['action_dispatch.remote_ip'].to_s)
        end
        @caller = Utils::QueryStringParser.parse_caller(args)
        super
      end

      def format_attributes(args)
        record = args[:params][:data][:attributes].permit(@collection.fields.keys).to_h
        relations = {}

        args[:params][:data][:relationships]&.to_unsafe_h&.map do |field, value|
          schema = @collection.fields[field]

          record[schema.foreign_key] = value[:data][schema.foreign_key_target] if schema.type == 'ManyToOne'
        end

        [record, relations]
      end
    end
  end
end
