module ForestAdminDatasourceZendesk
  # HTTP-level wrapper around the zendesk_api gem.
  #
  # Error policy:
  # - "Critical" methods (count, fetch_ticket_comments) raise APIError on any
  #   failure other than 404. Returning a safe default would silently corrupt
  #   the data the user is looking at — better to surface a 500 than to mislead.
  # - "Best-effort" methods (bulk user/org lookups, schema introspection)
  #   log a warning and degrade to a safe default. These are enrichment paths;
  #   missing data shows up as nil/empty in the UI rather than crashing the
  #   whole page render.
  class Client
    MAX_PER_PAGE = 100

    def initialize(configuration)
      @configuration = configuration
    end

    # ---------- Search (critical) ----------

    # `opts` accepts: :query (required), :sort_by, :sort_order, :page,
    # :per_page. We use an options hash rather than five named args so the
    # call sites (the Searchable mixin) stay tidy and the signature stays
    # narrow.
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

    # ---------- Writes (critical) ----------
    #
    # All writes go through `api.connection` rather than the gem's resource
    # objects (`api.tickets.create!`, etc.) for two reasons:
    # 1. The collections already build flattened payloads; a hash POST is the
    #    most direct path and matches how reads work today.
    # 2. The gem's `save!` mutates a stateful resource and returns true/false;
    #    we want the parsed response body so create can return the full record.

    def create_ticket(attributes) = post_resource('tickets', 'ticket', attributes)
    def update_ticket(id, attrs)  = put_resource('tickets', 'ticket', id, attrs)
    def delete_ticket(id)         = delete_resource('tickets', id)

    def create_user(attributes) = post_resource('users', 'user', attributes)
    def update_user(id, attrs)  = put_resource('users', 'user', id, attrs)
    def delete_user(id)         = delete_resource('users', id)

    def create_organization(attrs)     = post_resource('organizations', 'organization', attrs)
    def update_organization(id, attrs) = put_resource('organizations', 'organization', id, attrs)
    def delete_organization(id)        = delete_resource('organizations', id)

    # ---------- Direct fetches (404 -> nil; other errors propagate) ----------

    def find_ticket(id)
      api.tickets.find(id: id)
    rescue ZendeskAPI::Error::RecordNotFound
      nil
    end

    def find_user(id)
      api.users.find(id: id)
    rescue ZendeskAPI::Error::RecordNotFound
      nil
    end

    def find_organization(id)
      api.organizations.find(id: id)
    rescue ZendeskAPI::Error::RecordNotFound
      nil
    end

    # ---------- Bulk lookups (best-effort) ----------

    def fetch_user_emails(ids)
      best_effort('fetch_user_emails', default: {}) do
        bulk_show_many('users', ids) { |u| [u['id'], u['email']] }
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

    # ---------- Schema introspection (best-effort; runs at boot) ----------

    def fetch_ticket_fields
      best_effort('fetch_ticket_fields (custom fields will be unavailable)', default: []) do
        Array(api.connection.get('ticket_fields').body['ticket_fields'])
      end
    end

    def fetch_user_fields
      best_effort('fetch_user_fields (custom fields will be unavailable)', default: []) do
        Array(api.connection.get('user_fields').body['user_fields'])
      end
    end

    def fetch_organization_fields
      best_effort('fetch_organization_fields (custom fields will be unavailable)', default: []) do
        Array(api.connection.get('organization_fields').body['organization_fields'])
      end
    end

    def raw
      api
    end

    private

    def post_resource(path, key, attributes)
      must_succeed("create(#{path})") do
        body = api.connection.post(path) { |req| req.body = { key => attributes } }.body
        body[key] || body
      end
    end

    def put_resource(path, key, id, attributes)
      must_succeed("update(#{path}/#{id})") do
        body = api.connection.put("#{path}/#{id}") { |req| req.body = { key => attributes } }.body
        body[key] || body
      end
    end

    def delete_resource(path, id)
      must_succeed("delete(#{path}/#{id})") do
        api.connection.delete("#{path}/#{id}")
        true
      end
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
      # find_* methods rescue RecordNotFound themselves and return nil; if a
      # 404 reaches us here (for search/count), surface it like any other
      # failure rather than silently mapping to nil/zero.
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
