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
            headers: @headers,
            type: 'Success',
            message: message,
            refresh: { relationships: options.key?(:invalidated) ? options[:invalidated] : [] },
            html: options.key?(:html) ? options[:html] : nil
          }
        end

        def error(message: 'Error', options: {})
          {
            headers: @headers,
            type: 'Error',
            status: 400,
            message: message,
            html: options.key?(:html) ? options[:html] : nil
          }
        end

        def webhook(url:, method: 'POST', headers: {}, body: {})
          {
            headers: @headers,
            type: 'Webhook',
            webhook: {
              body: body,
              headers: headers,
              method: method,
              url: url
            }
          }
        end

        def file(content:, name: 'file', mime_type: 'application/octet-stream')
          {
            headers: @headers,
            type: 'File',
            name: name,
            mime_type: mime_type,
            stream: content
          }
        end

        def redirect_to(path:)
          {
            headers: @headers,
            type: 'Redirect',
            redirect_to: path
          }
        end
      end
    end
  end
end
