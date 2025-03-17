module ForestAdminRpcAgent
  module Middleware
    class Authentication
      def initialize(app)
        @app = app
      end

      def call(env)
        request = Rack::Request.new(env)
        signature = request.get_header('HTTP_X_SIGNATURE')
        # TODO: IMPLEMENTATION HTTP_X_TIMESTAMP (for replay attack)
        body = request.body.read
        request.body.rewind

        unless valid_signature?(signature, body)
          return [401, { 'Content-Type' => 'application/json' }, [{ error: 'Unauthorized' }.to_json]]
        end

        @app.call(env)
      end

      private

      def valid_signature?(signature, body)
        return false if signature.nil? || body.nil?

        expected_signature = OpenSSL::HMAC.hexdigest('SHA256', auth_secret, body)
        Rack::Utils.secure_compare(signature, expected_signature)
      end

      def auth_secret
        ForestAdminRpcAgent.config.auth_secret
      end
    end
  end
end
