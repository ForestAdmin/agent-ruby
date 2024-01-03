module ForestAdminDatasourceCustomizer
  module Decorators
    module Actions
      module ResultBuilder
        def success(message: 'Success', options: [])
          {
            type: 'Success',
            message: message,
            refresh: { relationships: options.key?(:invalidated) ? options[:invalidated] : [] },
            html: options.key?(:html) ? options[:html] : nil
          }
        end

        def error(message: 'Error', options: [])
          {
            type: 'Error',
            status: 400,
            message: message,
            html: options.key?(:html) ? options[:html] : nil
          }
        end

        def webhook(url:, method: 'POST', headers: [], body: [])
          {
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
            type: 'File',
            name: name,
            mime_type: mime_type,
            stream: content
          }
        end

        def redirect_to(path:)
          {
            type: 'Redirect',
            redirect_to: path
          }
        end
      end
    end
  end
end
