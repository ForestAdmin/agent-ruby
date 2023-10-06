module ForestAdminAgent
  module Routes
    class AbstractAuthenticatedRoute < AbstractRoute
      def build(_args = {})
        # args[:headers]['action_dispatch.remote_ip'].to_s
        Facades::Whitelist.check_ip('127.0.0.1')
      end
    end
  end
end
