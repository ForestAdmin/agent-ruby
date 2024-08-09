module ForestAdminDatasourceCustomizer
  module Decorators
    module Action
      class ResultBuilder
        def initialize
          @headers = {}
        end

        sig { params(key: String, value: String).returns(self) }
        def set_header(key, value)
          @headers[key] = value

          self
        end

        sig { params(message: String, options: Hash).returns(Hash) }
        def success(message: 'Success', options: {})
          {
            headers: @headers,
            type: 'Success',
            message: message,
            refresh: { relationships: options.key?(:invalidated) ? options[:invalidated] : [] },
            html: options.key?(:html) ? options[:html] : nil
          }
        end

        sig { params(message: String, options: Hash).returns(Hash) }
        def error(message: 'Error', options: {})
          {
            headers: @headers,
            type: 'Error',
            status: 400,
            message: message,
            html: options.key?(:html) ? options[:html] : nil
          }
        end

        sig { params(url: String, method: String, headers: Hash, body: Hash).returns(Hash) }
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

        sig { params(content: String, name: String, mime_type: String).returns(Hash) }
        def file(content:, name: 'file', mime_type: 'application/octet-stream')
          {
            headers: @headers,
            type: 'File',
            name: name,
            mime_type: mime_type,
            stream: content
          }
        end

        sig { params(path: String).returns(Hash) }
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
