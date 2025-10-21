module ForestAdminDatasourceCustomizer
  module Decorators
    module Action
      class ResultBuilder
        def initialize
          @headers = {}
        end

        def set_header(key, value)
          @headers[key] = value

          self
        end

        def success(message: 'Success', options: {})
          {
            response_headers: @headers,
            type: 'Success',
            message: message,
            invalidated: options.key?(:invalidated) ? options[:invalidated] : [],
            html: options.key?(:html) ? options[:html] : nil
          }
        end

        def error(message: 'Error', options: {})
          {
            response_headers: @headers,
            type: 'Error',
            message: message,
            html: options.key?(:html) ? options[:html] : nil
          }
        end

        def webhook(url:, method: 'POST', headers: {}, body: {})
          {
            response_headers: @headers,
            type: 'Webhook',
            body: body,
            headers: headers,
            method: method,
            url: url
          }
        end

        def file(content:, name: 'file', mime_type: 'application/octet-stream')
          {
            response_headers: @headers,
            type: 'File',
            name: name,
            mime_type: mime_type,
            stream: content
          }
        end

        def redirect_to(path:)
          {
            response_headers: @headers,
            type: 'Redirect',
            path: path
          }
        end
      end
    end
  end
end
