module ForestAdminDatasourceZendesk
  class Client
    module Writes
      def create_ticket(attributes) = post_resource('tickets', 'ticket', attributes)
      def update_ticket(id, attrs)  = put_resource('tickets', 'ticket', id, attrs)
      def delete_ticket(id)         = delete_resource('tickets', id)

      def create_user(attributes) = post_resource('users', 'user', attributes)
      def update_user(id, attrs)  = put_resource('users', 'user', id, attrs)
      def delete_user(id)         = delete_resource('users', id)

      def create_organization(attrs)     = post_resource('organizations', 'organization', attrs)
      def update_organization(id, attrs) = put_resource('organizations', 'organization', id, attrs)
      def delete_organization(id)        = delete_resource('organizations', id)

      private

      def post_resource(path, key, attributes)
        op = "create(#{path})"
        body = must_succeed(op) do
          api.connection.post(path) { |req| req.body = { key => attributes } }.body
        end
        extract_resource(body, key, op)
      end

      def put_resource(path, key, id, attributes)
        op = "update(#{path}/#{id})"
        body = must_succeed(op) do
          api.connection.put("#{path}/#{id}") { |req| req.body = { key => attributes } }.body
        end
        extract_resource(body, key, op)
      end

      # Zendesk wraps create/update responses in `{ "<resource>": { ... } }`.
      # An empty or differently-shaped body means the API contract broke —
      # surface a typed error rather than handing back a confusing envelope.
      def extract_resource(body, key, operation)
        resource = body[key] if body.is_a?(Hash)
        return resource if resource.is_a?(Hash)

        raise APIError,
              "Zendesk API #{operation} returned an unexpected body shape (missing '#{key}'): #{body.inspect}"
      end

      def delete_resource(path, id)
        must_succeed("delete(#{path}/#{id})") do
          api.connection.delete("#{path}/#{id}")
          true
        end
      end
    end
  end
end
