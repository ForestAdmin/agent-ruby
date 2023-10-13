module ForestAdminAgent
  module Routes
    class AbstractAuthenticatedRoute < AbstractRoute
      def build(args = {})
        if args.dig(:headers, 'action_dispatch.remote_ip')
          Facades::Whitelist.check_ip(args[:headers]['action_dispatch.remote_ip'].to_s)
        end
        super
      end
    end
  end
end
