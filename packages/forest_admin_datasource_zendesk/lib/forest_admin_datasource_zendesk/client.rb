module ForestAdminDatasourceZendesk
  class Client
    include Writes
    include Introspection

    MAX_PER_PAGE = 100

    def initialize(configuration)
      @configuration = configuration
    end

    def search(type, **opts)
      params = build_search_params(type, opts)
      must_succeed("search(#{type})") { api.search(params).to_a }
    end

    def count(type, query:)
      must_succeed("count(#{type})") do
        body = api.connection.get('search/count', query: compose_query(type, query)).body
        Integer(body['count'] || 0)
      end
    end

    def fetch_ticket_comments(ticket_id)
      must_succeed("fetch_ticket_comments(#{ticket_id})") do
        Array(api.connection.get("tickets/#{ticket_id}/comments").body['comments'])
      end
    end

    def find_ticket(id)       = find_one(api.tickets, id)
    def find_user(id)         = find_one(api.users, id)
    def find_organization(id) = find_one(api.organizations, id)

    def fetch_user_emails(ids)
      best_effort('fetch_user_emails', default: {}) do
        bulk_show_many('users', ids) { |u| [u['id'], u['email']] }
      end
    end

    def fetch_tickets_by_ids(ids)
      must_succeed('fetch_tickets_by_ids') do
        bulk_show_many('tickets', ids) { |t| [t['id'], t] }
      end
    end

    def fetch_users_by_ids(ids)
      best_effort('fetch_users_by_ids', default: {}) do
        bulk_show_many('users', ids) { |u| [u['id'], u] }
      end
    end

    def fetch_organizations_by_ids(ids)
      best_effort('fetch_organizations_by_ids', default: {}) do
        bulk_show_many('organizations', ids) { |o| [o['id'], o] }
      end
    end

    private

    def find_one(api_collection, id)
      api_collection.find(id: id)
    rescue ZendeskAPI::Error::RecordNotFound
      nil
    end

    def bulk_show_many(resource, ids)
      ids = Array(ids).compact.uniq
      return {} if ids.empty?

      ids.each_slice(MAX_PER_PAGE).with_object({}) do |batch, acc|
        body = api.connection.get("#{resource}/show_many", ids: batch.join(',')).body
        Array(body[resource]).each do |item|
          k, v = yield(item)
          acc[k] = v
        end
      end
    end

    def must_succeed(operation)
      yield
    rescue StandardError => e
      raise APIError, "Zendesk API call failed: #{operation}: #{e.class}: #{e.message}"
    end

    def best_effort(operation, default:)
      yield
    rescue StandardError => e
      ForestAdminDatasourceZendesk.logger.warn(
        "[forest_admin_datasource_zendesk] #{operation} failed; degrading: #{e.class}: #{e.message}"
      )
      default
    end

    def compose_query(type, query)
      [type ? "type:#{type}" : nil, query.to_s.strip].compact.reject(&:empty?).join(' ')
    end

    def build_search_params(type, opts)
      params = {
        query: compose_query(type, opts[:query]),
        per_page: [opts[:per_page] || MAX_PER_PAGE, MAX_PER_PAGE].min,
        page: opts[:page] || 1
      }
      params[:sort_by]    = opts[:sort_by]    if opts[:sort_by]
      params[:sort_order] = opts[:sort_order] if opts[:sort_order]
      params
    end

    def api
      @api ||= ZendeskAPI::Client.new do |c|
        c.url      = @configuration.url
        c.username = @configuration.username
        c.token    = @configuration.token
        c.retry    = true
      end
    end
  end
end
