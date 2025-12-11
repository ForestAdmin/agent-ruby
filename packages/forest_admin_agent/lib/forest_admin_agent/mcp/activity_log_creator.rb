require 'faraday'
require 'json'

module ForestAdminAgent
  module Mcp
    class ActivityLogCreator
      ACTION_TO_TYPE = {
        'index' => 'read',
        'search' => 'read',
        'filter' => 'read',
        'listHasMany' => 'read',
        'actionForm' => 'read',
        'action' => 'write',
        'create' => 'write',
        'update' => 'write',
        'delete' => 'write',
        'availableActions' => 'read',
        'availableCollections' => 'read'
      }.freeze

      def self.create(forest_server_url, auth_info, action, extra = {})
        type = ACTION_TO_TYPE[action]
        raise "Unknown action type: #{action}" unless type

        forest_server_token = auth_info.dig(:extra, :forest_server_token)
        rendering_id = auth_info.dig(:extra, :rendering_id)

        client = Faraday.new(forest_server_url) do |conn|
          conn.headers['Content-Type'] = 'application/json'
          conn.headers['Forest-Application-Source'] = 'MCP'
          conn.headers['Authorization'] = "Bearer #{forest_server_token}"
        end

        records = extra[:record_ids] || (extra[:record_id] ? [extra[:record_id]] : [])

        payload = {
          data: {
            id: 1,
            type: 'activity-logs-requests',
            attributes: {
              type: type,
              action: action,
              label: extra[:label],
              records: records.map(&:to_s)
            }.compact,
            relationships: {
              rendering: {
                data: {
                  id: rendering_id.to_s,
                  type: 'renderings'
                }
              },
              collection: {
                data: if extra[:collection_name]
                        {
                          id: extra[:collection_name],
                          type: 'collections'
                        }
                      end
              }
            }
          }
        }

        response = client.post('/api/activity-logs-requests', payload.to_json)

        return if response.success?

        Facades::Container.logger.log(
          'Warn',
          "[MCP] Failed to create activity log: #{response.body}"
        )
      end
    end
  end
end
