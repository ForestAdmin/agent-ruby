require 'json'

module ForestAdminRpcAgent
  module Middleware
    class Authentication
      ALLOWED_TIME_DIFF = 300

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

        status, headers, response = @app.call(env)

        if request.get_header('HTTP_FOREST_CALLER')
          caller = ForestAdminDatasourceToolkit::Components::Caller.new(
            **(JSON.parse(request.get_header('HTTP_FOREST_CALLER')).symbolize_keys)
          )
          headers = headers.merge({ caller: caller })
        end

        [status, headers, response]
      end

      private

      def valid_signature?(signature, timestamp)
        return false if signature.nil? || timestamp.nil?
        return false unless valid_timestamp?(timestamp)

        expected_signature = OpenSSL::HMAC.hexdigest('SHA256', auth_secret, timestamp)

        Rack::Utils.secure_compare(signature, expected_signature)
      end

      def valid_timestamp?(timestamp)
        time = begin
          Time.iso8601(timestamp).utc
        rescue ArgumentError
          nil
        end
        return false if time.nil?

        (current_time_in_seconds - time.to_i).abs <= ALLOWED_TIME_DIFF
      end

      def current_time_in_seconds
        defined?(Time.current) ? Time.current.to_i : Time.now.utc.to_i
      end

      def auth_secret
        ForestAdminRpcAgent.config.auth_secret
      end
    end
  end
end
