module ForestAdminAgent
  module Mcp
    class ErrorParser
      def self.parse(error)
        return error.message if error.is_a?(StandardError)

        parse_from_string(error.to_s)
      end

      def self.parse_from_string(error_string)
        return nil if error_string.nil? || error_string.empty?

        # Try to parse as JSON
        begin
          parsed = JSON.parse(error_string)
          return extract_from_json(parsed)
        rescue JSON::ParserError
          # Not JSON, return as-is
          return error_string
        end
      end

      def self.extract_from_json(parsed)
        # Handle JSON:API error format
        if parsed.is_a?(Hash) && parsed['errors'].is_a?(Array)
          errors = parsed['errors']
          return errors.map { |e| e['detail'] || e['title'] || e['name'] }.compact.join(', ')
        end

        # Handle simple error object
        if parsed.is_a?(Hash)
          return parsed['detail'] || parsed['message'] || parsed['error'] || parsed.to_s
        end

        parsed.to_s
      end
    end
  end
end
