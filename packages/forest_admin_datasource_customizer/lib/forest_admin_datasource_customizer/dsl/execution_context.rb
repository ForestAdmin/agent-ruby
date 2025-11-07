# frozen_string_literal: true

module ForestAdminDatasourceCustomizer
  module DSL
    # ExecutionContext provides a cleaner API for action execution blocks
    # It wraps the context and result_builder to provide direct access to common methods
    #
    # @example
    #   collection.action :export do
    #     execute do
    #       format = form_value(:format)
    #       data = generate_export(format)
    #       file content: data, name: "export.#{format}"
    #     end
    #   end
    class ExecutionContext
      attr_reader :context, :result_builder, :result

      def initialize(context, result_builder)
        @context = context
        @result_builder = result_builder
        @result = nil
      end

      # Access form values by field name
      # @param key [String, Symbol] the field name
      # @return [Object] the form field value
      def form_value(key)
        @context.form_value(key.to_s)
      end

      # Access the datasource for querying other collections
      # @return [Object] the datasource
      def datasource
        @context.datasource
      end

      # Access caller information (user, permissions, etc.)
      # @return [Object] the caller context
      def caller
        @context.caller
      end

      # Return a success result
      # @param message [String] success message
      # @param invalidated [Array<String>] collections to invalidate
      # @param html [String] optional HTML content
      # @return [Hash] the success result
      def success(message = 'Success', invalidated: nil, html: nil)
        options = {}
        options[:invalidated] = invalidated if invalidated && !invalidated.empty?
        options[:html] = html if html

        @result = @result_builder.success(
          message: message,
          options: options
        )
      end

      # Return an error result
      # @param message [String] error message
      # @param html [String] optional HTML content
      # @return [Hash] the error result
      def error(message = 'Error', html: nil)
        options = {}
        options[:html] = html if html

        @result = @result_builder.error(
          message: message,
          options: options
        )
      end

      # Return a file download result
      # @param content [String] file content
      # @param name [String] file name
      # @param mime_type [String] MIME type
      # @return [Hash] the file result
      def file(content:, name: 'file', mime_type: 'application/octet-stream')
        @result = @result_builder.file(
          content: content,
          name: name,
          mime_type: mime_type
        )
      end

      # Return a webhook result
      # @param url [String] webhook URL
      # @param method [String] HTTP method
      # @param headers [Hash] HTTP headers
      # @param body [Hash] request body
      # @return [Hash] the webhook result
      def webhook(url, method: 'POST', headers: {}, body: {})
        @result = @result_builder.webhook(
          url: url,
          method: method,
          headers: headers,
          body: body
        )
      end

      # Return a redirect result
      # @param path [String] redirect path
      # @return [Hash] the redirect result
      def redirect(path)
        @result = @result_builder.redirect_to(path: path)
      end

      # Set a response header
      # @param key [String] header name
      # @param value [String] header value
      # @return [ExecutionContext] self for chaining
      def set_header(key, value)
        @result_builder.set_header(key, value)
        self
      end
    end
  end
end
