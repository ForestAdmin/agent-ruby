module ForestAdminRpcAgent
  module Middleware
    class Authentication
      ALLOWED_TIME_DIFF = 300
      @@used_signatures = {}

      def initialize(app)
        @app = app
      end

      def call(env)
        request = Rack::Request.new(env)
        signature = request.get_header('HTTP_X_SIGNATURE')
        timestamp = request.get_header('HTTP_X_TIMESTAMP')

        unless valid_signature?(signature, timestamp)
          return [401, { 'Content-Type' => 'application/json' }, [{ error: 'Unauthorized' }.to_json]]
        end

        @app.call(env)
      end

      private

      def valid_signature?(signature, timestamp)
        return false if signature.nil? || timestamp.nil?

        return false unless valid_timestamp?(timestamp)

        expected_signature = OpenSSL::HMAC.hexdigest('SHA256', auth_secret, timestamp)

        return false unless Rack::Utils.secure_compare(signature, expected_signature)

        # check if this signature has already been used (replay attack)
        return false if @@used_signatures.key?(signature)

        @@used_signatures[signature] = Time.now.utc.to_i

        cleanup_old_signatures

        true
      end

      def valid_timestamp?(timestamp)
        time = begin
          Time.iso8601(timestamp)
        rescue StandardError
          nil
        end
        return false if time.nil?

        (Time.now.utc.to_i - time.to_i).abs <= ALLOWED_TIME_DIFF
      end

      def cleanup_old_signatures
        now = Time.now.utc.to_i
        @@used_signatures.delete_if { |_key, timestamp| now - timestamp > ALLOWED_TIME_DIFF }
      end

      def auth_secret
        ForestAdminRpcAgent.config.auth_secret
      end
    end
  end
end
