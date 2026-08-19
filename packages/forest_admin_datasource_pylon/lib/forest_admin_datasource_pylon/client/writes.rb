module ForestAdminDatasourcePylon
  class Client
    # The write half of the client: one explicit method per Pylon write
    # endpoint, each delegating to the shared helpers below.
    #
    # Nothing here degrades. `best_effort` exists for the calls whose result
    # enriches a page — a thread that could not be read costs a column — where a
    # write that silently did nothing would tell the operator their edit landed.
    #
    # Pylon exposes no write endpoint for every verb: there is no POST or DELETE
    # on users, and no DELETE on teams. The collections answer those, not the
    # client, which only spells the endpoints that exist.
    module Writes
      # `title` and `body_html` are the two fields POST /issues requires.
      def create_issue(attributes) = post_resource('issues', attributes)
      def update_issue(id, attributes) = patch_resource('issues', id, attributes)
      def delete_issue(id) = delete_resource('issues', id)

      def create_account(attributes) = post_resource('accounts', attributes)
      def update_account(id, attributes) = patch_resource('accounts', id, attributes)
      def delete_account(id) = delete_resource('accounts', id)

      def create_contact(attributes) = post_resource('contacts', attributes)
      def update_contact(id, attributes) = patch_resource('contacts', id, attributes)
      def delete_contact(id) = delete_resource('contacts', id)

      def create_team(attributes) = post_resource('teams', attributes)
      def update_team(id, attributes) = patch_resource('teams', id, attributes)

      def update_user(id, attributes) = patch_resource('users', id, attributes)

      private

      def post_resource(resource, attributes)
        operation = "create(#{resource})"

        must_succeed(operation) { extract_written(connection.post(resource, attributes).body, operation) }
      end

      # The id comes from the record the operator acted on, so it is escaped
      # before being joined to the path, like every read does.
      def patch_resource(resource, id, attributes)
        path      = "#{resource}/#{Faraday::Utils.escape(id)}"
        operation = "update(#{path})"

        must_succeed(operation) { extract_written(connection.patch(path, attributes).body, operation) }
      end

      # Answers true rather than the body: Pylon returns 200 or 204 with nothing
      # worth reading, and a caller has no record left to serialize.
      def delete_resource(resource, id)
        path = "#{resource}/#{Faraday::Utils.escape(id)}"

        must_succeed("delete(#{path})") do
          connection.delete(path)
          true
        end
      end

      # Pylon answers a write with the written record under `data`. Anything else
      # means the contract broke, which is worth a typed error rather than an
      # envelope the collection would then serialize into a record with no id --
      # `extract_data` hands the body back untouched when `data` is absent, which
      # is what a read wants and a write must not accept.
      def extract_written(body, operation)
        record = body['data'] if body.is_a?(Hash)
        return record if record.is_a?(Hash)

        raise APIError,
              "Pylon API #{operation} returned an unexpected body shape (missing 'data'): #{body.inspect}"
      end
    end
  end
end
