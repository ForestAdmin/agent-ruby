module ForestAdminAgent
  module Routes
    class AbstractAuthenticatedRoute < AbstractRoute
      def build(args = {})
        # TODO: handle call permissions
        Facades::Whitelist.check_ip(args[:headers]['action_dispatch.remote_ip'].to_s)
      end
    end
  end
end
