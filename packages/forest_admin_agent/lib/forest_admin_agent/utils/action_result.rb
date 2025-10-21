module ForestAdminAgent
  module Utils
    module ActionResult
      def self.parse(result)
        keys = {}
        case result[:type]
          when 'Success'
            keys = {
              success: result[:message],
              refresh: { relationships: result[:invalidated] },
              html: result[:html]
            }
          when 'Error'
            keys = {
              status: 400,
              error: result[:message],
              html: result[:html]
            }
          when 'Webhook'
            keys= {
              webhook: {
                body: result[:body],
                headers: result[:headers],
                method: result[:method],
                url: result[:url]
              }
            }
          when 'File'
            keys = {
              name: result[:name],
              mime_type: result[:mime_type],
              stream: result[:content]
            }
          when 'Redirect'
            keys = {
              redirect_to: result[:path]
            }
        end
        keys.merge({ headers: result[:response_headers] })
      end
    end
  end
end
