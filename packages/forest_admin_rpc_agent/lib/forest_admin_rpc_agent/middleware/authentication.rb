module ForestAdminRpcAgent
  module Middleware
    class Authentication
      ALLOWED_TIME_DIFF = 300
      SIGNATURE_REUSE_WINDOW = 5
      @@used_signatures = {}
      @@signatures_mutex = Mutex.new

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
        # Reject if signature was used recently (within SIGNATURE_REUSE_WINDOW seconds)
        # Use mutex to prevent race conditions in multi-threaded environments
        now = current_time_in_seconds

        @@signatures_mutex.synchronize do
          if @@used_signatures.key?(signature)
            last_used = @@used_signatures[signature]
            time_since_last_use = now - last_used
            return false if time_since_last_use <= SIGNATURE_REUSE_WINDOW
          end
          @@used_signatures[signature] = now

          cleanup_old_signatures
        end

        true
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

      def cleanup_old_signatures
        # Should be called within mutex synchronize block
        now = current_time_in_seconds
        @@used_signatures.delete_if { |_signature, last_used| now - last_used > ALLOWED_TIME_DIFF }
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
